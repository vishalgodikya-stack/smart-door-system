"""
models.py — Pydantic schemas for request/response validation
Smart Door Security System
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel, EmailStr


# ─── Auth / User ────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: "UserOut"


class PinVerifyRequest(BaseModel):
    pin: str


class OTPVerifyRequest(BaseModel):
    otp_code: str


class PinSetupRequest(BaseModel):
    pin: str


class UserOut(BaseModel):
    id: int
    name: str
    email: str
    role: str
    is_active: bool
    fcm_token: Optional[str] = None
    created_at: datetime
    has_pin: bool
    has_totp: bool

    class Config:
        from_attributes = True


class UserUpdate(BaseModel):
    name: Optional[str] = None
    role: Optional[str] = None
    is_active: Optional[bool] = None
    fcm_token: Optional[str] = None


# ─── Invite ──────────────────────────────────────────────────────────────────────

class InviteCreateRequest(BaseModel):
    role: str            # admin / member / viewer
    email: Optional[str] = None


class InviteOut(BaseModel):
    token: str
    role: str
    email: Optional[str]
    invite_url: str
    expires_at: Optional[datetime]
    created_at: datetime

    class Config:
        from_attributes = True


# ─── Door ────────────────────────────────────────────────────────────────────────

class DoorStatusOut(BaseModel):
    status: str          # locked / unlocked
    last_updated: datetime


class DoorActionRequest(BaseModel):
    reason: Optional[str] = None


# ─── Alert ───────────────────────────────────────────────────────────────────────

class AlertOut(BaseModel):
    id: int
    image_url: str
    status: str
    decided_by_name: Optional[str]
    decision_at: Optional[datetime]
    created_at: datetime

    class Config:
        from_attributes = True


class AlertDecisionRequest(BaseModel):
    decision: str        # approve / reject


# ─── Access Log ──────────────────────────────────────────────────────────────────

class LogOut(BaseModel):
    id: int
    person_name: Optional[str]
    type: str
    action: Optional[str]
    image_url: Optional[str]
    performed_by_name: Optional[str]
    created_at: datetime

    class Config:
        from_attributes = True


# ─── Authorized Person ───────────────────────────────────────────────────────────

class PersonOut(BaseModel):
    id: int
    name: str
    photo_url: Optional[str]
    added_by_name: Optional[str]
    added_at: datetime

    class Config:
        from_attributes = True


class PersonCreateRequest(BaseModel):
    name: str


# ─── WebSocket Event ─────────────────────────────────────────────────────────────

class WSEvent(BaseModel):
    event: str           # new_alert / door_status / alert_updated
    data: dict
