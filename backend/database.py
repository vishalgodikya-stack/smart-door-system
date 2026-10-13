"""
database.py — SQLite database setup using SQLAlchemy
Smart Door Security System
"""
import os
from datetime import datetime

from sqlalchemy import (
    Boolean, Column, DateTime, ForeignKey, Integer, LargeBinary, String, Text, create_engine
)
from sqlalchemy.orm import DeclarativeBase, Session, relationship, sessionmaker
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./smart_door.db")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},  # needed for SQLite
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)


class Base(DeclarativeBase):
    pass


# ─── ORM Models ────────────────────────────────────────────────────────────────

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    email = Column(String(200), unique=True, nullable=False, index=True)
    password_hash = Column(String(200), nullable=False)
    pin_hash = Column(String(200), nullable=True)
    totp_secret = Column(String(100), nullable=True)
    role = Column(String(20), default="viewer")   # admin / member / viewer
    invite_token = Column(String(100), nullable=True, unique=True)
    is_active = Column(Boolean, default=True)
    fcm_token = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    decisions = relationship("Alert", back_populates="decided_by_user", foreign_keys="Alert.decided_by")
    logs = relationship("AccessLog", back_populates="performed_by_user", foreign_keys="AccessLog.performed_by")


class AuthorizedPerson(Base):
    __tablename__ = "authorized_persons"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    photo_path = Column(String(300), nullable=True)
    face_encoding = Column(LargeBinary, nullable=True)  # numpy array serialized
    added_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    added_at = Column(DateTime, default=datetime.utcnow)

    added_by_user = relationship("User", foreign_keys=[added_by])


class Alert(Base):
    __tablename__ = "alerts"

    id = Column(Integer, primary_key=True, index=True)
    image_path = Column(String(300), nullable=False)
    status = Column(String(20), default="pending")  # pending / approved / rejected
    decided_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    decision_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    decided_by_user = relationship("User", foreign_keys=[decided_by], back_populates="decisions")


class AccessLog(Base):
    __tablename__ = "access_logs"

    id = Column(Integer, primary_key=True, index=True)
    person_name = Column(String(100), nullable=True)
    type = Column(String(20), nullable=False)    # authorized / unauthorized
    action = Column(String(30), nullable=True)   # auto_opened / approved / rejected / pin_used / otp_used
    image_path = Column(String(300), nullable=True)
    performed_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    performed_by_user = relationship("User", foreign_keys=[performed_by], back_populates="logs")


class DoorState(Base):
    __tablename__ = "door_state"

    id = Column(Integer, primary_key=True, default=1)
    status = Column(String(10), default="locked")  # locked / unlocked
    last_updated = Column(DateTime, default=datetime.utcnow)
    changed_by = Column(Integer, ForeignKey("users.id"), nullable=True)


class Invite(Base):
    __tablename__ = "invites"

    id = Column(Integer, primary_key=True, index=True)
    token = Column(String(100), unique=True, nullable=False)
    role = Column(String(20), nullable=False)
    email = Column(String(200), nullable=True)
    used = Column(Boolean, default=False)
    created_by = Column(Integer, ForeignKey("users.id"), nullable=True)
    expires_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


# ─── DB Init ────────────────────────────────────────────────────────────────────

def create_tables():
    Base.metadata.create_all(bind=engine)


def get_db():
    """FastAPI dependency — yields a DB session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
