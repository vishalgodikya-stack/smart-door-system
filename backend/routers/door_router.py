"""
routers/door_router.py — Door lock/unlock control + status
"""
from datetime import datetime

import asyncio
import os
import secrets
from fastapi import APIRouter, Depends, BackgroundTasks, Header, HTTPException
from sqlalchemy.orm import Session

from auth import get_current_user, require_member_or_above
from database import AccessLog, DoorState, User, get_db, SessionLocal
from models import DoorActionRequest, DoorStatusOut
from websocket_manager import manager

router = APIRouter()

# Try to import GPIO (only works on Raspberry Pi)
try:
    import RPi.GPIO as GPIO
    import os
    DOOR_PIN = int(os.getenv("DOOR_GPIO_PIN", 18))
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(DOOR_PIN, GPIO.OUT, initial=GPIO.LOW)  # LOW = Locked (Relay OFF)
    GPIO_AVAILABLE = True
    print(f"[GPIO] Door pin {DOOR_PIN} initialized")
except (ImportError, RuntimeError):
    GPIO_AVAILABLE = False
    print("[GPIO] RPi.GPIO not available — running in simulation mode")


async def _set_door(db: Session, status: str, user_id: int, user_name: str):
    """Update door state in DB, control GPIO, and broadcast to WebSocket clients."""
    door = db.query(DoorState).filter(DoorState.id == 1).first()
    if door:
        door.status = status
        door.last_updated = datetime.utcnow()
        door.changed_by = user_id
        db.commit()

    if GPIO_AVAILABLE:
        import RPi.GPIO as GPIO
        if status == "unlocked":
            GPIO.output(DOOR_PIN, GPIO.HIGH)  # Relay ON = Unlocked
        else:
            GPIO.output(DOOR_PIN, GPIO.LOW)   # Relay OFF = Locked

    await manager.broadcast("door_status", {"status": status, "changed_by": user_name})


async def auto_lock_door(user_id: int, user_name: str, delay: int = 7):
    """Background task to wait `delay` seconds and automatically relock the door."""
    await asyncio.sleep(delay)

    # Must use a fresh session because the request session is already closed!
    db = SessionLocal()
    try:
        door = db.query(DoorState).filter(DoorState.id == 1).first()
        if door and door.status == "unlocked":
            await _set_door(db, "locked", user_id, "Auto-Lock (Timer)")
            print(f"[AUTO-LOCK] Door locked automatically after {delay} seconds.")
    finally:
        db.close()


@router.get("/status", response_model=DoorStatusOut)
def door_status(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    door = db.query(DoorState).filter(DoorState.id == 1).first()
    return DoorStatusOut(status=door.status, last_updated=door.last_updated)


@router.post("/unlock")
async def unlock_door(
    background_tasks: BackgroundTasks,
    body: DoorActionRequest = DoorActionRequest(),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_member_or_above),
):
    await _set_door(db, "unlocked", current_user.id, current_user.name)

    log = AccessLog(
        person_name=current_user.name,
        type="authorized",
        action="remote_unlock",
        performed_by=current_user.id,
    )
    db.add(log)
    db.commit()

    # Start the auto-lock background timer
    background_tasks.add_task(auto_lock_door, current_user.id, current_user.name)

    return {"message": "Door unlocked (Will auto-lock in 7s)", "status": "unlocked"}


@router.post("/lock")
async def lock_door(
    body: DoorActionRequest = DoorActionRequest(),
    db: Session = Depends(get_db),
    current_user: User = Depends(require_member_or_above),
):
    await _set_door(db, "locked", current_user.id, current_user.name)

    log = AccessLog(
        person_name=current_user.name,
        type="authorized",
        action="remote_lock",
        performed_by=current_user.id,
    )
    db.add(log)
    db.commit()
    return {"message": "Door locked", "status": "locked"}


@router.post("/auto-unlock")
async def auto_unlock_door(
    body: dict,
    background_tasks: BackgroundTasks,
    x_backend_token: str = Header(default="", alias="X-Backend-Token"),
    db: Session = Depends(get_db),
):
    """Unlock the door after a recognized face from the Pi face watcher."""
    expected_token = os.getenv("BACKEND_TOKEN", "")

    if expected_token and not secrets.compare_digest(x_backend_token, expected_token):
        raise HTTPException(status_code=401, detail="Invalid backend token")

    person_name = str(body.get("person_name", "")).strip()
    if not person_name:
        raise HTTPException(status_code=400, detail="person_name is required")

    await _set_door(db, "unlocked", None, person_name)

    log = AccessLog(
        person_name=person_name,
        type="authorized",
        action="auto_opened",
        performed_by=None,
    )
    db.add(log)
    db.commit()

    background_tasks.add_task(
        auto_lock_door,
        None,
        "Auto-Lock (Face Recognition)",
    )

    return {
        "message": f"Authorized face detected: {person_name}",
        "status": "unlocked",
    }
