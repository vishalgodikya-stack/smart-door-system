"""
face_watcher.py — Raspberry Pi 4 camera loop with face recognition
Runs continuously, capturing frames and identifying faces.
Uploads unknown faces to the FastAPI backend and supports live face enrollment.

Requirements (install on RPi):
  pip install face_recognition picamera2 requests Pillow numpy

Run: python face_watcher.py
"""
import io
import os
import pickle
import time
import requests
import numpy as np
from datetime import datetime
from PIL import Image

# ─── Config ──────────────────────────────────────────────────────────────────────
API_URL = os.getenv("API_URL", "http://localhost:8000")
BACKEND_TOKEN = os.getenv("BACKEND_TOKEN", "")  # Internal token for RPi → API
FACE_TOLERANCE = float(os.getenv("FACE_RECOGNITION_TOLERANCE", 0.6))
CAPTURE_INTERVAL = 1.5         # seconds between captures during normal monitoring
ENROLL_CAPTURE_INTERVAL = 0.1  # seconds between captures (~10 FPS) during live enrollment
ENROLL_TIMEOUT = 60.0          # auto-expire enrollment flag after 60 seconds

LATEST_FRAME_PATH = "/dev/shm/latest_frame.jpg"
ENROLL_FLAG_PATH = "/dev/shm/enrollment_active"
RELOAD_FLAG_PATH = "/dev/shm/reload_faces"

from picamera2 import Picamera2
import face_recognition


# ─── Helpers ─────────────────────────────────────────────────────────────────────

def load_known_faces() -> tuple[list, list]:
    """Load all authorized persons' face encodings from the local SQLite database."""
    known_encodings = []
    known_names = []

    try:
        from sqlalchemy import create_engine
        from sqlalchemy.orm import sessionmaker
        import sys
        backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        if backend_dir not in sys.path:
            sys.path.insert(0, backend_dir)
        from database import AuthorizedPerson

        db_path = os.path.join(backend_dir, "smart_door.db")
        engine = create_engine(f"sqlite:///{db_path}", connect_args={"check_same_thread": False})
        Session = sessionmaker(bind=engine)
        db = Session()

        persons_db = db.query(AuthorizedPerson).all()
        for p in persons_db:
            if p.face_encoding:
                encoding = pickle.loads(p.face_encoding)
                known_encodings.append(encoding)
                known_names.append(p.name)

        db.close()
        print(f"[FACES] Loaded {len(known_names)} known faces: {known_names}")
    except Exception as e:
        print(f"[ERROR] Failed to load known faces from DB: {e}")

    return known_encodings, known_names


def _is_enrollment_active() -> bool:
    """Check if the app currently has an active live face enrollment session."""
    if not os.path.exists(ENROLL_FLAG_PATH):
        return False
    try:
        mtime = os.path.getmtime(ENROLL_FLAG_PATH)
        if time.time() - mtime > ENROLL_TIMEOUT:
            os.remove(ENROLL_FLAG_PATH)
            print("[ENROLL] Enrollment session timed out after 60s — resuming normal monitoring")
            return False
        return True
    except Exception:
        return False


def _save_latest_frame(rgb_frame: np.ndarray):
    """Atomically write the latest RGB frame to RAM disk (/dev/shm/latest_frame.jpg)."""
    tmp_path = f"{LATEST_FRAME_PATH}.tmp"
    try:
        Image.fromarray(rgb_frame).save(tmp_path, format="JPEG", quality=80)
        os.replace(tmp_path, LATEST_FRAME_PATH)
    except Exception:
        pass


def send_alert(image_bytes: bytes):
    """Upload unauthorized visitor image to FastAPI backend."""
    try:
        files = {"file": ("visitor.jpg", image_bytes, "image/jpeg")}
        resp = requests.post(
            f"{API_URL}/alerts/from-camera",
            files=files,
            timeout=10,
        )
        print(f"[ALERT] Sent to backend: {resp.status_code}")
    except Exception as e:
        print(f"[ERROR] Failed to send alert: {e}")


# ─── Main Loop ───────────────────────────────────────────────────────────────────

def main():
    print("[STARTUP] Smart Door Face Watcher starting...")

    picam2 = Picamera2()
    picam2.configure(picam2.create_still_configuration(main={"size": (640, 480)}))
    picam2.start()

    # Reload known faces every 10 seconds or immediately after enrollment
    known_encodings, known_names = load_known_faces()
    last_reload = time.time()
    RELOAD_INTERVAL = 10  # 10 seconds

    alert_cooldown = {}  # prevent spam alerts
    was_enrolling = False

    try:
        while True:
            enrolling = _is_enrollment_active()

            # Capture frame (Picamera2 returns RGB array)
            frame = picam2.capture_array()
            rgb_frame = frame

            # Save latest frame for live enrollment stream and access requests
            _save_latest_frame(rgb_frame)

            # During live enrollment, stream at ~10 FPS and pause intruder alerts/unlocking
            if enrolling:
                if not was_enrolling:
                    print("[ENROLL] Live face enrollment active — streaming at 10 FPS")
                    was_enrolling = True
                time.sleep(ENROLL_CAPTURE_INTERVAL)
                continue

            # If enrollment just finished or a reload flag was set, reload encodings immediately
            if was_enrolling or os.path.exists(RELOAD_FLAG_PATH):
                was_enrolling = False
                if os.path.exists(RELOAD_FLAG_PATH):
                    try:
                        os.remove(RELOAD_FLAG_PATH)
                    except Exception:
                        pass
                print("[ENROLL] Reloading known faces after enrollment/update...")
                known_encodings, known_names = load_known_faces()
                last_reload = time.time()

            # Periodic reload every 5 minutes
            if time.time() - last_reload > RELOAD_INTERVAL:
                known_encodings, known_names = load_known_faces()
                last_reload = time.time()

            # Detect faces
            face_locations = face_recognition.face_locations(rgb_frame)
            if not face_locations:
                time.sleep(CAPTURE_INTERVAL)
                continue

            face_encodings = face_recognition.face_encodings(rgb_frame, face_locations)

            for face_encoding in face_encodings:
                matches = face_recognition.compare_faces(known_encodings, face_encoding, tolerance=FACE_TOLERANCE)
                distances = face_recognition.face_distance(known_encodings, face_encoding)

                if len(distances) > 0 and True in matches:
                    best_idx = int(np.argmin(distances))
                    if matches[best_idx]:
                        name = known_names[best_idx]
                        print(f"[✅ AUTHORIZED] {name} — Unlocking door")

                        # Trigger auto-unlock on backend (backend handles GPIO + logging + WebSockets)
                        try:
                            headers = {"X-Backend-Token": BACKEND_TOKEN}
                            requests.post(
                                f"{API_URL}/door/auto-unlock",
                                json={"person_name": name},
                                headers=headers,
                                timeout=5,
                            )
                        except Exception as e:
                            print(f"[ERROR] Failed to send auto-unlock request: {e}")
                        continue

                now = time.time()
                cooldown_key = "unknown"
                if now - alert_cooldown.get(cooldown_key, 0) < 30:
                    print("[SKIP] Alert on cooldown")
                    continue

                print("[⚠️  UNAUTHORIZED] Unknown face — sending alert")
                alert_cooldown[cooldown_key] = now

                # Convert frame to JPEG bytes
                pil_img = Image.fromarray(rgb_frame)
                buf = io.BytesIO()
                pil_img.save(buf, format="JPEG", quality=85)
                send_alert(buf.getvalue())

            time.sleep(CAPTURE_INTERVAL)

    except KeyboardInterrupt:
        print("\n[SHUTDOWN] Face watcher stopped")
    finally:
        picam2.stop()


if __name__ == "__main__":
    main()
