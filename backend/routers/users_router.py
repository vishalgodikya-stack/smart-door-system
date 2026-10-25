"""
routers/users_router.py — User management (Admin only)
"""
from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from auth import get_current_user, hash_password, require_admin
from database import User, get_db
from models import UserCreateRequest, UserOut, UserUpdate

router = APIRouter()


def _user_out(user: User) -> UserOut:
    return UserOut(
        id=user.id,
        name=user.name,
        username=user.username,
        role=user.role,
        is_active=user.is_active,
        is_logged_in=user.is_logged_in,
        fcm_token=user.fcm_token,
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


@router.post("", response_model=UserOut)
def create_user(
    body: UserCreateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    clean_role = body.role.strip().lower()
    if clean_role not in ("admin", "member"):
        raise HTTPException(status_code=400, detail="Invalid role. Must be 'admin' or 'member'")

    if clean_role == "admin":
        admin_count = db.query(User).filter(User.role == "admin").count()
        if admin_count >= 2:
            raise HTTPException(
                status_code=400,
                detail="Maximum 2 admins allowed. Remove an existing admin first.",
            )

    clean_username = body.username.strip().lower()
    if not clean_username:
        raise HTTPException(status_code=400, detail="Username cannot be empty")
    if " " in clean_username:
        raise HTTPException(status_code=400, detail="Username cannot contain spaces")
    if not body.password or not body.password.strip():
        raise HTTPException(status_code=400, detail="Password cannot be empty")

    existing = db.query(User).filter(User.username == clean_username).first()
    if existing:
        raise HTTPException(status_code=400, detail=f"Username '{clean_username}' already exists")

    new_user = User(
        name=body.username.strip().capitalize(),
        username=clean_username,
        password_hash=hash_password(body.password),
        role=clean_role,
        is_active=True,
        is_logged_in=False,
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return _user_out(new_user)


@router.post("/{user_id}/reset-session")
def reset_user_session(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(require_admin),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    user.is_logged_in = False
    db.commit()
    return {
        "message": f"Session for '{user.username}' reset successfully",
        "user_id": user_id,
        "is_logged_in": False,
    }


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
        clean_role = body.role.strip().lower()
        if clean_role not in ("admin", "member"):
            raise HTTPException(status_code=400, detail="Invalid role")
        if clean_role == "admin" and user.role != "admin":
            admin_count = db.query(User).filter(User.role == "admin").count()
            if admin_count >= 2:
                raise HTTPException(
                    status_code=400,
                    detail="Maximum 2 admins allowed. Remove an existing admin first.",
                )
        if clean_role == "member" and user.role == "admin":
            admin_count = db.query(User).filter(User.role == "admin").count()
            if admin_count <= 1:
                raise HTTPException(
                    status_code=400,
                    detail="Cannot demote the last remaining admin.",
                )
        user.role = clean_role
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

    if user.role == "admin":
        admin_count = db.query(User).filter(User.role == "admin").count()
        if admin_count <= 1:
            raise HTTPException(
                status_code=400,
                detail="Cannot delete the last remaining admin.",
            )

    username = user.username
    from database import Alert, AccessLog, AuthorizedPerson, DoorState
    db.query(Alert).filter(Alert.decided_by == user_id).update({Alert.decided_by: None})
    db.query(AccessLog).filter(AccessLog.performed_by == user_id).update({AccessLog.performed_by: None})
    db.query(AuthorizedPerson).filter(AuthorizedPerson.added_by == user_id).update({AuthorizedPerson.added_by: None})
    db.query(DoorState).filter(DoorState.changed_by == user_id).update({DoorState.changed_by: None})

    db.delete(user)
    db.commit()
    return {"message": f"User '{username}' removed"}
