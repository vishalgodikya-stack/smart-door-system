"""
routers/alerts_router.py — Alerts CRUD and approve/reject decisions
"""
import os
from datetime import datetime
from typing import List

from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, UploadFile, File
from sqlalchemy.orm import Session
from firebase_admin import messaging
import uuid
import shutil

from auth import get_current_user, require_member_or_above
from database import AccessLog, Alert, User, get_db
from models import AlertOut
from websocket_manager import manager

router = APIRouter()

BASE_URL = os.getenv("BASE_URL", "http://localhost:8000")


def _alert_to_out(alert: Alert) -> AlertOut:
    return AlertOut(
        id=alert.id,
        image_url=f"{BASE_URL}/images/{os.path.basename(alert.image_path)}",
        status=alert.status,
        decided_by_name=alert.decided_by_user.name if alert.decided_by_user else None,
        decision_at=alert.decision_at,
        created_at=alert.created_at,
    )


@router.get("", response_model=List[AlertOut])
def list_alerts(
    skip: int = 0,
    limit: int = 50,
    status: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(Alert)
    if status:
        query = query.filter(Alert.status == status)
    alerts = query.order_by(Alert.created_at.desc()).offset(skip).limit(limit).all()
    return [_alert_to_out(a) for a in alerts]


@router.get("/{alert_id}", response_model=AlertOut)
def get_alert(
    alert_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    alert = db.query(Alert).filter(Alert.id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    return _alert_to_out(alert)


@router.post("/{alert_id}/approve")
async def approve_alert(
    alert_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_member_or_above),
):
    alert = db.query(Alert).filter(Alert.id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    if alert.status != "pending":
        raise HTTPException(status_code=400, detail="Alert already decided")

    alert.status = "approved"
    alert.decided_by = current_user.id
    alert.decision_at = datetime.utcnow()

    # Shared door logic from door_router limits duplicated GPIO code
    from routers.door_router import _set_door, auto_lock_door
    await _set_door(db, "unlocked", current_user.id, current_user.name)

    log = AccessLog(
        type="unauthorized",
        action="approved",
        image_path=alert.image_path,
        performed_by=current_user.id,
    )
    db.add(log)
    db.commit()

    # Broadcast alert specific update
    await manager.broadcast("alert_updated", {"id": alert_id, "status": "approved"})

    # Set background task to auto-lock the door after 7s
    background_tasks.add_task(auto_lock_door, current_user.id, "Auto-Lock (Timer)")

    return {"message": "Access approved — Door unlocked for 7 seconds"}


@router.post("/{alert_id}/reject")
async def reject_alert(
    alert_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_member_or_above),
):
    alert = db.query(Alert).filter(Alert.id == alert_id).first()
    if not alert:
        raise HTTPException(status_code=404, detail="Alert not found")
    if alert.status != "pending":
        raise HTTPException(status_code=400, detail="Alert already decided")

    alert.status = "rejected"
    alert.decided_by = current_user.id
    alert.decision_at = datetime.utcnow()

    log = AccessLog(
        type="unauthorized",
        action="rejected",
        image_path=alert.image_path,
        performed_by=current_user.id,
    )
    db.add(log)
    db.commit()

    await manager.broadcast("alert_updated", {"id": alert_id, "status": "rejected"})
    return {"message": "Access rejected"}


async def send_push_notification(db: Session, title: str, body: str, data: dict = None, image_url: str = None):
    """Sends a push notification to all admin and member users who have a registered FCM token."""
    users = db.query(User).filter(User.fcm_token != None, User.role.in_(["admin", "member"])).all()
    tokens = list({u.fcm_token for u in users if u.fcm_token})

    if not tokens:
        print("[FCM] No registered device tokens found.")
        return

    notification_kwargs = {
        "title": title,
        "body": body,
    }
    if image_url:
        notification_kwargs["image"] = image_url

    android_notification_kwargs = {
        "channel_id": "security_alerts",
        "priority": "max",
        "default_sound": True,
        "default_vibrate_timings": True,
    }
    if image_url:
        android_notification_kwargs["image"] = image_url

    android_config = messaging.AndroidConfig(
        priority="high",
        notification=messaging.AndroidNotification(**android_notification_kwargs),
    )

    message = messaging.MulticastMessage(
        notification=messaging.Notification(**notification_kwargs),
        android=android_config,
        data=data or {},
        tokens=tokens,
    )
    try:
        response = messaging.send_each_for_multicast(message)
        print(f"[FCM] Successfully sent {response.success_count} notifications (failed: {response.failure_count})")
        if response.failure_count > 0:
            for idx, resp in enumerate(response.responses):
                if not resp.success:
                    print(f"[FCM] Token #{idx} failed: {resp.exception}")
    except Exception as e:
        print(f"[FCM] Error sending notifications: {e}")


@router.post("/request-access")
async def request_access(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """Called to request the door be opened. Triggers an alert."""
    images_dir = os.environ.get("IMAGES_DIR", "./images")
    os.makedirs(images_dir, exist_ok=True)

    filename = f"visitor_{uuid.uuid4().hex}.jpg"
    filepath = os.path.join(images_dir, filename)

    if os.path.exists("/dev/shm/latest_frame.jpg"):
        shutil.copy2("/dev/shm/latest_frame.jpg", filepath)
    else:
        from PIL import Image
        img = Image.new('RGB', (640, 480), color=(73, 109, 137))
        img.save(filepath)

    alert = Alert(
        image_path=filepath,
        status="pending"
    )
    db.add(alert)
    db.commit()
    db.refresh(alert)

    out_dict = _alert_to_out(alert).dict()
    out_dict["created_at"] = out_dict["created_at"].isoformat()
    if out_dict["decision_at"]:
        out_dict["decision_at"] = out_dict["decision_at"].isoformat()

    await manager.broadcast("new_alert", out_dict)

    image_url = f"{BASE_URL}/images/{filename}"
    title = "👋 Access Request"
    body = f"{current_user.name} is requesting access to the front door!"
    await send_push_notification(
        db,
        title,
        body,
        {"alert_id": str(alert.id), "type": "new_alert", "image_url": image_url},
        image_url=image_url,
    )

    return {"message": "Access request sent successfully", "id": alert.id}


@router.post("/from-camera")
async def receive_camera_alert(
    file: UploadFile = File(...),
    db: Session = Depends(get_db)
):
    """Internal endpoint used by face_watcher.py to post an unauthorized visitor photo."""
    images_dir = os.environ.get("IMAGES_DIR", "./images")
    os.makedirs(images_dir, exist_ok=True)

    # Save the file
    ext = file.filename.split('.')[-1] if '.' in file.filename else 'png'
    filename = f"visitor_{uuid.uuid4().hex}.{ext}"
    filepath = os.path.join(images_dir, filename)

    with open(filepath, "wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    # Create the alert record
    alert = Alert(
        image_path=filepath,
        status="pending"
    )
    db.add(alert)
    db.commit()
    db.refresh(alert)

    # Broadcast to all flutter apps!
    out_dict = _alert_to_out(alert).dict()
    out_dict["created_at"] = out_dict["created_at"].isoformat()
    if out_dict["decision_at"]:
        out_dict["decision_at"] = out_dict["decision_at"].isoformat()

    await manager.broadcast("new_alert", out_dict)

    # Send Push Notification!
    image_url = f"{BASE_URL}/images/{filename}"
    await send_push_notification(
        db,
        "🔔 Someone at the Door",
        "Someone is at the door! Tap to allow or deny entry.",
        {"alert_id": str(alert.id), "type": "new_alert", "image_url": image_url},
        image_url=image_url,
    )

    return {"message": "Alert received and broadcasted", "id": alert.id}


@router.delete("")
def clear_alerts(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_member_or_above),
):
    alerts = db.query(Alert).all()
    for alert in alerts:
        if alert.image_path and os.path.exists(alert.image_path):
            try:
                os.remove(alert.image_path)
            except Exception:
                pass
    db.query(Alert).delete()
    db.commit()

    return {"message": "All alerts cleared"}
