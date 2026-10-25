"""
main.py — FastAPI application entry point
Smart Door Security System Backend
"""
import os
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
import firebase_admin
from firebase_admin import credentials

from auth import decode_token, hash_password
from database import DoorState, SessionLocal, User, create_tables
from websocket_manager import manager

from routers import auth_router, door_router, alerts_router, persons_router, users_router, media_router

load_dotenv()

IMAGES_DIR = os.getenv("IMAGES_DIR", "./images")
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "admin@smartdoor.local")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "changeme123")


# ─── Firebase Init ──────────────────────────────────────────────────────────────

firebase_creds_path = "firebase-service-account.json"
if os.path.exists(firebase_creds_path):
    try:
        # Check if already initialized to prevent reloader errors
        if not firebase_admin._apps:
            cred = credentials.Certificate(firebase_creds_path)
            firebase_admin.initialize_app(cred)
            print("[FIREBASE] Admin SDK initialized successfully")
        else:
            print("[FIREBASE] Admin SDK already initialized")
    except Exception as e:
        print(f"[FIREBASE] Error initializing Admin SDK: {e}")
else:
    print("[FIREBASE] Warning: firebase-service-account.json not found. Push notifications disabled.")


# ─── Startup ─────────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create tables and seed initial admin on startup."""
    create_tables()
    os.makedirs(IMAGES_DIR, exist_ok=True)
    os.makedirs("./known_faces", exist_ok=True)

    db = SessionLocal()
    try:
        # Seed admin account if not exists
        if not db.query(User).filter(User.role == "admin").first():
            admin = User(
                name="System Admin",
                email=ADMIN_EMAIL,
                password_hash=hash_password(ADMIN_PASSWORD),
                role="admin",
                is_active=True,
            )
            db.add(admin)

        # Seed demo member if not exists
        if not db.query(User).filter(User.email == "member@smartdoor.com").first():
            member = User(
                name="Demo Member",
                email="member@smartdoor.com",
                password_hash=hash_password("member123"),
                role="member",
                is_active=True,
            )
            db.add(member)

        # Migrate any legacy viewer accounts to member
        db.query(User).filter(User.role == "viewer").update({"role": "member"})

        # Init door state if not exists
        if not db.query(DoorState).first():
            db.add(DoorState(id=1, status="locked"))

        db.commit()
        print(f"[STARTUP] Admin account: {ADMIN_EMAIL}")
        print("[STARTUP] Smart Door backend is ready ✅")
    finally:
        db.close()

    # Start Doorbell background listener
    try:
        from doorbell import start_doorbell, stop_doorbell
        start_doorbell()
    except Exception as e:
        print(f"[DOORBELL] Failed to start listener: {e}")

    yield  # App runs

    # Stop Doorbell background listener
    try:
        from doorbell import stop_doorbell
        stop_doorbell()
    except Exception:
        pass
    print("[SHUTDOWN] Smart Door backend stopped.")


# ─── App ─────────────────────────────────────────────────────────────────────────

app = FastAPI(
    title="Smart Door Security System API",
    description="Self-hosted backend for Smart Door IoT system",
    version="1.0.0",
    lifespan=lifespan,
)

# Allow Flutter app to connect from any origin (configure for production)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve visitor images as static files
app.mount("/static", StaticFiles(directory=IMAGES_DIR), name="static")

# ─── Routers ─────────────────────────────────────────────────────────────────────

app.include_router(auth_router.router, prefix="/auth", tags=["Authentication"])
app.include_router(door_router.router, prefix="/door", tags=["Door Control"])
app.include_router(alerts_router.router, prefix="/alerts", tags=["Alerts"])
app.include_router(persons_router.router, prefix="/persons", tags=["Authorized Persons"])
app.include_router(users_router.router, prefix="/users", tags=["User Management"])
app.include_router(media_router.router, prefix="/images", tags=["Media"])
app.include_router(media_router.logs_router, tags=["Logs"])


# ─── WebSocket ────────────────────────────────────────────────────────────────────

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """
    All connected Flutter apps subscribe here for real-time events.
    Events: new_alert, door_status, alert_updated
    """
    await manager.connect(websocket)
    try:
        # Optionally authenticate via token in first message
        while True:
            data = await websocket.receive_text()
            # Echo heartbeat to keep connection alive
            await manager.send_to(websocket, "pong", {})
    except WebSocketDisconnect:
        manager.disconnect(websocket)


# ─── Health ──────────────────────────────────────────────────────────────────────

@app.get("/", tags=["Health"])
async def root():
    return {
        "status": "online",
        "app": "Smart Door Security System",
        "version": "1.0.0",
        "docs": "/docs",
    }


@app.get("/health", tags=["Health"])
async def health():
    return {"status": "healthy"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
