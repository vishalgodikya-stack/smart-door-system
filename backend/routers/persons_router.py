"""
routers/persons_router.py — Authorized persons management & live camera face enrollment
"""
import io
import os
import pickle
import re
import time
from typing import List

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.encoders import jsonable_encoder
from pydantic import BaseModel
from sqlalchemy.orm import Session

from auth import get_current_user, require_admin
from database import AuthorizedPerson, User, get_db
from models import PersonOut

router = APIRouter()

BASE_URL = os.getenv("BASE_URL", "http://localhost:8000")
IMAGES_DIR = os.getenv("IMAGES_DIR", "./images")
KNOWN_FACES_DIR = "./known_faces"

SHM_DIR = "/dev/shm" if os.path.isdir("/dev/shm") else IMAGES_DIR
LATEST_FRAME_PATH = os.path.join(SHM_DIR, "latest_frame.jpg")
ENROLL_FLAG_PATH = os.path.join(SHM_DIR, "enrollment_active")
RELOAD_FLAG_PATH = os.path.join(SHM_DIR, "reload_faces")


class EnrollScanRequest(BaseModel):
    name: str
    step: str = "detect"  # "detect" or "register"


def _person_out(p: AuthorizedPerson) -> PersonOut:
    return PersonOut(
        id=p.id,
        name=p.name,
        photo_url=f"{BASE_URL}/images/{os.path.basename(p.photo_path)}" if p.photo_path else None,
        added_by_name=p.added_by_user.name if p.added_by_user else None,
        added_at=p.added_at,
    )


def _touch_flag(path: str):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(str(time.time()))


def _remove_flag(path: str):
    if os.path.exists(path):
        try:
            os.remove(path)
        except Exception:
            pass


@router.get("", response_model=List[PersonOut])
def list_persons(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    persons = db.query(AuthorizedPerson).order_by(AuthorizedPerson.added_at.desc()).all()
    return [_person_out(p) for p in persons]


@router.post("/enroll/start")
def start_face_enrollment(
    current_user: User = Depends(require_admin),
):
    """Start live camera face enrollment session (signals face_watcher to stream at 10 FPS)."""
    _touch_flag(ENROLL_FLAG_PATH)
    return {
        "status": "started",
        "message": "Camera stream started. Position face in front of the camera.",
    }


@router.post("/enroll/stop")
def stop_face_enrollment(
    current_user: User = Depends(require_admin),
):
    """Stop live camera face enrollment session and resume normal security monitoring."""
    _remove_flag(ENROLL_FLAG_PATH)
    return {
        "status": "stopped",
        "message": "Enrollment camera stream stopped.",
    }


@router.get("/enroll/frame")
def get_enrollment_frame(
    current_user: User = Depends(require_admin),
):
    """Fetch the latest live frame captured by the Raspberry Pi camera."""
    if os.path.exists(ENROLL_FLAG_PATH):
        _touch_flag(ENROLL_FLAG_PATH)

    frame_path = LATEST_FRAME_PATH
    if not os.path.exists(frame_path):
        fallback = os.path.join(IMAGES_DIR, "latest_frame.jpg")
        if os.path.exists(fallback):
            frame_path = fallback
        else:
            raise HTTPException(status_code=404, detail="Camera stream waiting for frame")

    try:
        with open(frame_path, "rb") as f:
            data = f.read()
    except Exception:
        raise HTTPException(status_code=503, detail="Frame temporarily busy")

    if not data:
        raise HTTPException(status_code=503, detail="Empty camera frame")

    return Response(
        content=data,
        media_type="image/jpeg",
        headers={
            "Cache-Control": "no-store, no-cache, must-revalidate, max-age=0",
            "Pragma": "no-cache",
        },
    )


@router.post("/enroll/scan")
def scan_and_enroll_face(
    req: EnrollScanRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    """
    Detect and scan a face from the live Raspberry Pi camera feed.
    - step='detect': Verifies a single clear face is positioned in front of the camera.
    - step='register': Extracts the 128-D face encoding, saves the image + DB record, and stops stream.
    """
    clean_name = req.name.strip()
    if not clean_name:
        raise HTTPException(status_code=400, detail="Full name is required for face registration")

    _touch_flag(ENROLL_FLAG_PATH)

    frame_path = LATEST_FRAME_PATH
    if not os.path.exists(frame_path):
        fallback = os.path.join(IMAGES_DIR, "latest_frame.jpg")
        if os.path.exists(fallback):
            frame_path = fallback
        else:
            return {
                "status": "positioning",
                "message": "Waiting for live camera stream from Raspberry Pi...",
            }

    try:
        with open(frame_path, "rb") as f:
            frame_bytes = f.read()
    except Exception:
        return {
            "status": "positioning",
            "message": "Capturing frame — please hold still...",
        }

    if not frame_bytes:
        return {
            "status": "positioning",
            "message": "Capturing frame — please hold still...",
        }

    try:
        import face_recognition

        img = face_recognition.load_image_file(io.BytesIO(frame_bytes))
        locations = face_recognition.face_locations(img)

        if len(locations) == 0:
            return {
                "status": "positioning",
                "message": "Positioning face — please look directly at the camera",
            }

        if len(locations) > 1:
            return {
                "status": "positioning",
                "message": "Multiple faces detected — only one person should be in front of the camera",
            }

        top, right, bottom, left = locations[0]
        face_height = bottom - top
        face_width = right - left
        if face_height < 60 or face_width < 60:
            return {
                "status": "positioning",
                "message": "Face is too far — please step closer to the camera",
            }

        if req.step == "detect":
            return {
                "status": "scanning",
                "message": "Face detected! Scanning facial features — hold still...",
            }

        encodings = face_recognition.face_encodings(img, locations)
        if not encodings:
            return {
                "status": "positioning",
                "message": "Could not scan facial features clearly — please hold still and look at the camera",
            }

        encoding_bytes = pickle.dumps(encodings[0])

    except ImportError:
        raise HTTPException(
            status_code=500,
            detail="face_recognition library is not installed on the backend server",
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Face scan error: {e}",
        )

    # Save the enrolled face photo and database record
    os.makedirs(IMAGES_DIR, exist_ok=True)
    os.makedirs(KNOWN_FACES_DIR, exist_ok=True)

    safe_name = re.sub(r"[^a-z0-9_]+", "_", clean_name.lower()).strip("_") or "person"
    filename = f"person_{safe_name}_{int(time.time())}.jpg"
    filepath = os.path.join(IMAGES_DIR, filename)

    with open(filepath, "wb") as f:
        f.write(frame_bytes)

    person = AuthorizedPerson(
        name=clean_name,
        photo_path=filepath,
        face_encoding=encoding_bytes,
        added_by=current_user.id,
    )
    db.add(person)
    db.commit()
    db.refresh(person)

    # Stop enrollment mode and signal face_watcher to reload known faces immediately
    _remove_flag(ENROLL_FLAG_PATH)
    _touch_flag(RELOAD_FLAG_PATH)

    return {
        "status": "registered",
        "message": f"Registration successful! {clean_name} has been added to Authorized Persons.",
        "person": jsonable_encoder(_person_out(person)),
    }


@router.delete("/{person_id}")
def delete_person(
    person_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    person = db.query(AuthorizedPerson).filter(AuthorizedPerson.id == person_id).first()
    if not person:
        raise HTTPException(status_code=404, detail="Person not found")

    # Delete photo file
    if person.photo_path and os.path.exists(person.photo_path):
        try:
            os.remove(person.photo_path)
        except Exception:
            pass

    db.delete(person)
    db.commit()

    # Signal face_watcher to reload known faces
    _touch_flag(RELOAD_FLAG_PATH)

    return {"message": f"Removed {person.name} from authorized list"}
