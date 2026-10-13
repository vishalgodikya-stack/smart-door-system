"""
routers/media_router.py — Serve visitor images and log history
"""
import os
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from auth import get_current_user
from database import AccessLog, User, get_db
from models import LogOut

router = APIRouter()

IMAGES_DIR = os.getenv("IMAGES_DIR", "./images")
BASE_URL = os.getenv("BASE_URL", "http://localhost:8000")


@router.get("/{filename}")
def serve_image(filename: str):
    """Serve a visitor image file. (Unguessable UUID filename provides security)."""
    filepath = os.path.join(IMAGES_DIR, filename)
    if not os.path.exists(filepath):
        raise HTTPException(status_code=404, detail="Image not found")
    return FileResponse(filepath, media_type="image/jpeg")


# ─── Logs (bonus endpoint here to avoid a separate router file) ──────────────────

logs_router = APIRouter()


def _log_out(log: AccessLog) -> LogOut:
    return LogOut(
        id=log.id,
        person_name=log.person_name,
        type=log.type,
        action=log.action,
        image_url=f"{BASE_URL}/images/{os.path.basename(log.image_path)}" if log.image_path else None,
        performed_by_name=log.performed_by_user.name if log.performed_by_user else None,
        created_at=log.created_at,
    )


@logs_router.get("/logs", response_model=List[LogOut])
def list_logs(
    skip: int = 0,
    limit: int = 100,
    type: str = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = db.query(AccessLog)
    if type:
        query = query.filter(AccessLog.type == type)
    logs = query.order_by(AccessLog.created_at.desc()).offset(skip).limit(limit).all()
    return [_log_out(l) for l in logs]
