"""
routers/auth_router.py — Login, registration via invite, PIN/OTP setup & verify
"""
import io
import secrets
from datetime import datetime, timedelta

import qrcode
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session

from auth import (
    create_access_token, get_current_user, hash_password, hash_pin,
    verify_password, verify_pin, verify_totp, generate_totp_secret, get_totp_uri
)
from database import Invite, User, get_db
from models import (
    LoginRequest, OTPVerifyRequest, PinSetupRequest, PinVerifyRequest,
    RegisterRequest, TokenResponse, UserOut
)

router = APIRouter()


def _user_out(user: User) -> UserOut:
    return UserOut(
        id=user.id,
        name=user.name,
        email=user.email,
        role=user.role,
        is_active=user.is_active,
        fcm_token=user.fcm_token,
        created_at=user.created_at,
        has_pin=user.pin_hash is not None,
        has_totp=user.totp_secret is not None,
    )


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == body.email, User.is_active == True).first()
    if not user or not verify_password(body.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    token = create_access_token(user.id, user.role)
    return TokenResponse(access_token=token, user=_user_out(user))


@router.post("/register/{invite_token}", response_model=TokenResponse)
def register(invite_token: str, body: RegisterRequest, db: Session = Depends(get_db)):
    invite = db.query(Invite).filter(
        Invite.token == invite_token,
        Invite.used == False,
    ).first()
    if not invite:
        raise HTTPException(status_code=400, detail="Invalid or expired invite link")
    if invite.expires_at and invite.expires_at < datetime.utcnow():
        raise HTTPException(status_code=400, detail="Invite link has expired")

    existing = db.query(User).filter(User.email == body.email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

    user = User(
        name=body.name,
        email=body.email,
        password_hash=hash_password(body.password),
        role=invite.role,
    )
    db.add(user)
    invite.used = True
    db.commit()
    db.refresh(user)

    token = create_access_token(user.id, user.role)
    return TokenResponse(access_token=token, user=_user_out(user))


@router.get("/me", response_model=UserOut)
def me(current_user: User = Depends(get_current_user)):
    return _user_out(current_user)


@router.patch("/me/fcm-token")
def update_fcm_token(
    token_data: dict,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """Update the FCM token for the current logged-in user."""
    fcm_token = token_data.get("fcm_token")
    if not fcm_token:
        raise HTTPException(status_code=400, detail="fcm_token is required")
    
    current_user.fcm_token = fcm_token
    db.commit()
    return {"message": "FCM token updated successfully"}


@router.post("/setup-pin")
def setup_pin(body: PinSetupRequest, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    if len(body.pin) < 4:
        raise HTTPException(status_code=400, detail="PIN must be at least 4 digits")
    current_user.pin_hash = hash_pin(body.pin)
    db.commit()
    return {"message": "PIN set successfully"}


@router.post("/verify-pin")
def verify_pin_endpoint(body: PinVerifyRequest, db: Session = Depends(get_db)):
    """
    Used by the door system to verify PIN when face recognition fails.
    Returns a short-lived token if PIN is valid.
    """
    users = db.query(User).filter(User.pin_hash != None, User.is_active == True).all()
    for user in users:
        if verify_pin(body.pin, user.pin_hash):
            token = create_access_token(user.id, user.role, expires_delta=timedelta(minutes=5))
            return {"valid": True, "token": token, "user": _user_out(user)}
    raise HTTPException(status_code=401, detail="Invalid PIN")


@router.post("/setup-totp")
def setup_totp(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    secret = generate_totp_secret()
    current_user.totp_secret = secret
    db.commit()

    uri = get_totp_uri(secret, current_user.email)
    img = qrcode.make(uri)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    buf.seek(0)
    return StreamingResponse(buf, media_type="image/png")


@router.post("/verify-otp")
def verify_otp_endpoint(body: OTPVerifyRequest, db: Session = Depends(get_db)):
    """Verify TOTP code without requiring a JWT — used for fallback access."""
    users = db.query(User).filter(User.totp_secret != None, User.is_active == True).all()
    for user in users:
        if verify_totp(user.totp_secret, body.otp_code):
            token = create_access_token(user.id, user.role, expires_delta=timedelta(minutes=5))
            return {"valid": True, "token": token, "user": _user_out(user)}
    raise HTTPException(status_code=401, detail="Invalid OTP code")
