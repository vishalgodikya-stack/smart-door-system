"""
models.py — Pydantic schemas for request/response validation
Smart Door Security System
"""
from datetime import datetime
from typing import Optional
from pydantic import BaseModel


# ─── Auth / User ────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    username: str
    password: str


class UserCreateRequest(BaseModel):
    username: str
    password: str
    role: str = "member"


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
    username: str
    role: str
    is_active: bool
    is_logged_in: bool = False
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
    alert_type: str = "doorbell"
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
