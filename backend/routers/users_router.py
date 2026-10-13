"""
routers/users_router.py — User management and invite system (Admin only)
"""
import secrets
from datetime import datetime, timedelta
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from auth import get_current_user, require_admin
from database import Invite, User, get_db
from models import InviteCreateRequest, InviteOut, UserOut, UserUpdate

router = APIRouter()

import os
BASE_URL = os.getenv("BASE_URL", "http://localhost:8000")


def _user_out(user: User) -> UserOut:
    return UserOut(
        id=user.id,
        name=user.name,
        email=user.email,
        role=user.role,
        is_active=user.is_active,
        created_at=user.created_at,
        has_pin=user.pin_hash is not None,
        has_totp=user.totp_secret is not None,
    )


@router.get("", response_model=List[UserOut])
def list_users(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    users = db.query(User).order_by(User.created_at).all()
    return [_user_out(u) for u in users]


@router.patch("/{user_id}", response_model=UserOut)
def update_user(
    user_id: int,
    body: UserUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot modify your own account here")

    if body.name is not None:
        user.name = body.name
    if body.role is not None:
        if body.role not in ("admin", "member", "viewer"):
            raise HTTPException(status_code=400, detail="Invalid role")
        user.role = body.role
    if body.is_active is not None:
        user.is_active = body.is_active

    db.commit()
    db.refresh(user)
    return _user_out(user)


@router.delete("/{user_id}")
def delete_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="Cannot delete your own account")
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    db.delete(user)
    db.commit()
    return {"message": f"User {user.email} removed"}


@router.post("/invite", response_model=InviteOut)
def create_invite(
    body: InviteCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    if body.role not in ("admin", "member", "viewer"):
        raise HTTPException(status_code=400, detail="Invalid role")

    token = secrets.token_urlsafe(32)
    expires = datetime.utcnow() + timedelta(days=7)

    invite = Invite(
        token=token,
        role=body.role,
        email=body.email,
        created_by=current_user.id,
        expires_at=expires,
    )
    db.add(invite)
    db.commit()
    db.refresh(invite)

    invite_url = f"{BASE_URL}/auth/register/{token}"
    return InviteOut(
        token=invite.token,
        role=invite.role,
        email=invite.email,
        invite_url=invite_url,
        expires_at=invite.expires_at,
        created_at=invite.created_at,
    )


@router.get("/invites")
def list_invites(
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    invites = db.query(Invite).order_by(Invite.created_at.desc()).limit(20).all()
    return [
        {
            "token": i.token[:8] + "...",
            "role": i.role,
            "email": i.email,
            "used": i.used,
            "expires_at": i.expires_at,
        }
        for i in invites
    ]
