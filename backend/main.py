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
from database import DoorState, SessionLocal, User, create_tables, engine
from websocket_manager import manager

from routers import auth_router, door_router, alerts_router, persons_router, users_router, media_router

load_dotenv()

IMAGES_DIR = os.getenv("IMAGES_DIR", "./images")
os.makedirs(IMAGES_DIR, exist_ok=True)
os.makedirs("./known_faces", exist_ok=True)


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


# ─── DB Migration ────────────────────────────────────────────────────────────────

def migrate_database():
    """Migrate legacy SQLite database schema to username-based auth and remove legacy tables."""
    with engine.connect() as conn:
        cols = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(users)").fetchall()]
        if "email" in cols:
            try:
                conn.exec_driver_sql("UPDATE access_logs SET performed_by = NULL WHERE performed_by IN (SELECT id FROM users)")
                conn.commit()
            except Exception:
                pass
            conn.exec_driver_sql("DROP TABLE IF EXISTS users")
            conn.commit()
        try:
            conn.exec_driver_sql("DROP TABLE IF EXISTS invites")
            conn.commit()
        except Exception:
            pass

    create_tables()

    with engine.connect() as conn:
        cols = [row[1] for row in conn.exec_driver_sql("PRAGMA table_info(users)").fetchall()]
        if "username" not in cols:
            conn.exec_driver_sql("ALTER TABLE users ADD COLUMN username VARCHAR(50)")
            conn.commit()
        if "is_logged_in" not in cols:
            conn.exec_driver_sql("ALTER TABLE users ADD COLUMN is_logged_in BOOLEAN DEFAULT 0 NOT NULL")
            conn.commit()


# ─── Startup ─────────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Run DB migrations, purge legacy accounts, seed 2 initial admins on startup."""
    migrate_database()
    os.makedirs(IMAGES_DIR, exist_ok=True)
    os.makedirs("./known_faces", exist_ok=True)

    db = SessionLocal()
    try:
        # Purge legacy accounts
        db.query(User).filter(
            User.username.in_(["joe321@gmail.com", "member@smartdoor.com", "admin@smartdoor.local", "viewer@smartdoor.com"])
        ).delete(synchronize_session=False)
        db.query(User).filter(User.name.in_(["System Admin", "Demo Member"])).delete(synchronize_session=False)

        # Seed Admin 1: harish
        harish = db.query(User).filter(User.username == "harish").first()
        if not harish:
            harish = User(
                name="Harish",
                username="harish",
                password_hash=hash_password("harish123"),
                role="admin",
                is_active=True,
                is_logged_in=False,
            )
            db.add(harish)
            print("[STARTUP] Seeded admin: harish")

        # Seed Admin 2: vishal
        vishal = db.query(User).filter(User.username == "vishal").first()
        if not vishal:
            vishal = User(
                name="Vishal",
                username="vishal",
                password_hash=hash_password("vishal123"),
                role="admin",
                is_active=True,
                is_logged_in=False,
            )
            db.add(vishal)
            print("[STARTUP] Seeded admin: vishal")

        # Reset active login sessions on backend restart
        db.query(User).update({User.is_logged_in: False})

        # Init door state if not exists
        if not db.query(DoorState).first():
            db.add(DoorState(id=1, status="locked"))

        db.commit()
        print("[STARTUP] Initial Admins active: harish, vishal")
        print("[STARTUP] Smart Door backend is ready [READY]")
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
