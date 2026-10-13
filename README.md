# 🔐 IoT Smart Door Security System

An end-to-end IoT Smart Door Security System powered by **Raspberry Pi 4**, **Real-Time Face Recognition (`Picamera2` + `dlib`)**, **FastAPI + WebSockets**, **Firebase Cloud Messaging (FCM)**, and a **Flutter Mobile App** for remote monitoring, live camera face enrollment, and role-based access control.

---

## ✨ Key Features

- **Real-Time Face Recognition & Auto-Unlock**: Continuously monitors the door via the Raspberry Pi Camera (`Picamera2`), extracts 128-dimensional facial encodings (`dlib` / `face_recognition`), and automatically unlocks the 12V solenoid lock for authorized individuals (with a 7-second auto-relock timer).
- **Live Camera Face Enrollment (`Enroll Face` Tab)**: Admins can register new authorized persons directly from the mobile app using a live stream from the Raspberry Pi camera—detecting face positioning, scanning facial features, and storing the 128-D face encoding in SQLite without uploading static gallery photos.
- **Instant Intruder Alerts & Push Notifications**: Unknown faces trigger an instant alert with a captured visitor photo, broadcasted in real time via WebSockets and Firebase Cloud Messaging (FCM) push notifications.
- **Role-Based Access Control (RBAC)**:
  - **Admin**: Full door control, approve/reject alerts, live face enrollment, manage authorized persons & user invites.
  - **Member**: Lock/unlock door, approve/reject visitor alerts, view access logs.
  - **Viewer**: Read-only status & history viewing, plus a **Request Access** button that captures a live camera snapshot and notifies Admins.
- **Local Push-Button & Buzzer Doorbell**: Hardware doorbell loop running on the Raspberry Pi (`GPIO 23` input button + `GPIO 24` active buzzer).

---

## 📁 Project Structure

```text
smart-door-system/
├── backend/                        # FastAPI server & Raspberry Pi hardware modules
│   ├── face_recognition_module/
│   │   ├── door_controller.py      # Standalone GPIO 18 lock controller utility
│   │   └── face_watcher.py         # Picamera2 loop, face matching & live enrollment stream
│   ├── routers/
│   │   ├── auth_router.py          # JWT authentication, PIN & TOTP endpoints
│   │   ├── door_router.py          # GPIO 18 TIP122 lock control & 7s auto-lock timer
│   │   ├── alerts_router.py        # Intruder alerts, access requests & FCM notifications
│   │   ├── persons_router.py       # Authorized persons CRUD & live camera enrollment API
│   │   ├── media_router.py         # Visitor image serving (/images) & access history (/logs)
│   │   └── users_router.py         # User management & role-based invite links
│   ├── auth.py                     # Password hashing, JWT verification & role guards
│   ├── database.py                 # SQLAlchemy ORM models (SQLite)
│   ├── doorbell.py                 # Background GPIO 23/24 push-button & buzzer listener
│   ├── main.py                     # FastAPI entrypoint, WebSocket hub & lifespan hooks
│   ├── models.py                   # Pydantic request/response schemas
│   ├── websocket_manager.py        # Real-time WebSocket connection & broadcast manager
│   └── requirements.txt            # Python dependencies
└── smart_door_app/                 # Flutter mobile application (Android / iOS)
    └── lib/
        ├── config/api_config.dart  # Backend HTTPS & WebSocket endpoint definitions
        ├── models/                 # Dart data models (User, Alert, Log, Person)
        ├── providers/              # Riverpod state management (Auth, Door, Alerts)
        ├── screens/                # Dashboard, Enroll Face, Alerts, History, Persons, Users
        ├── services/               # REST API, Auth, WebSocket & FCM Notification services
        └── widgets/                # Reusable UI cards and role badges
```

---

## 🔌 Hardware Architecture & GPIO Wiring (Raspberry Pi 4)

### 1. Solenoid Door Lock Driver (`TIP122` NPN Darlington Transistor)
Because the Raspberry Pi 4 outputs `3.3V` logic (max ~16 mA per pin) while the solenoid lock requires `12V DC` (~500 mA–1 A), a **TIP122 NPN Darlington transistor** is used as a low-side switch with a **1N4007 flyback diode** across the solenoid terminals to suppress inductive kickback:

| Component / Signal | Raspberry Pi 4 Pin | Connection Details |
|---|---|---|
| **Door Control Signal** | `GPIO 18` (Physical Pin 12) | Connected to **TIP122 Base (Pin 1)** via a `1 kΩ` resistor |
| **Solenoid Negative (-)** | — | Connected to **TIP122 Collector (Pin 2)** + **1N4007 Anode** |
| **Solenoid Positive (+)** | — | Connected to **12V DC Adapter (+)** + **1N4007 Cathode (Silver Band)** |
| **Common Ground** | `GND` (Physical Pin 9) | Connected to **TIP122 Emitter (Pin 3)** and **12V DC Adapter (-)** |

### 2. Doorbell Push-Button & Buzzer
| Component | Raspberry Pi 4 Pin | Connection Details |
|---|---|---|
| **Push Button** | `GPIO 23` (Physical Pin 16) & `GND` (Pin 14) | Internal pull-up enabled (`active-LOW` when pressed) |
| **Active Buzzer** | `GPIO 24` (Physical Pin 18) & `GND` (Pin 20) | Driven `HIGH` while button is pressed |

---

## 🌐 API & WebSocket Endpoints

| Endpoint | Method | Access Role | Description |
|---|---|---|---|
| `/auth/login` | `POST` | Public | Authenticate with email & password and receive JWT |
| `/door/status` | `GET` | Any Authenticated | Get current door lock status (`locked` / `unlocked`) |
| `/door/unlock` | `POST` | Admin, Member | Remotely unlock door (`GPIO 18 HIGH`) with 7s auto-relock |
| `/door/lock` | `POST` | Admin, Member | Immediately lock door (`GPIO 18 LOW`) |
| `/door/auto-unlock` | `POST` | Face Watcher (`X-Backend-Token`) | Triggered by `face_watcher.py` upon recognizing an authorized face |
| `/persons` | `GET` / `DELETE` | Admin | View or remove registered authorized persons |
| `/persons/enroll/start` | `POST` | Admin | Start high-FPS live camera stream (`~10 FPS`) and pause intruder alerts |
| `/persons/enroll/frame` | `GET` | Admin | Fetch latest live JPEG frame from Raspberry Pi camera |
| `/persons/enroll/scan` | `POST` | Admin | Detect face positioning (`step="detect"`) or extract & save 128-D face encoding (`step="register"`) |
| `/persons/enroll/stop` | `POST` | Admin | Stop enrollment stream and resume normal security monitoring |
| `/alerts` | `GET` | Admin, Member | List intruder and access-request alerts |
| `/alerts/{id}/approve` | `POST` | Admin, Member | Approve visitor alert and unlock the door |
| `/alerts/{id}/reject` | `POST` | Admin, Member | Reject visitor alert |
| `/alerts/request-access` | `POST` | Viewer | Capture live visitor snapshot and notify Admins/Members |
| `/logs` | `GET` | Any Authenticated | View historical door access and alert logs |
| `/ws` | `WebSocket` | Any Authenticated | Real-time broadcast stream (`new_alert`, `door_status`, `alert_updated`) |

---

## 🖥️ Backend Setup (Raspberry Pi 4)

### 1. Install Dependencies
```bash
cd backend
cp .env.example .env
nano .env  # Configure SECRET_KEY, ADMIN_EMAIL, ADMIN_PASSWORD, BACKEND_TOKEN, BASE_URL

pip install -r requirements.txt
pip install RPi.GPIO picamera2 face_recognition numpy
```

### 2. Run the FastAPI Server & Face Watcher
```bash
# Start FastAPI backend (Port 8000)
python3 main.py

# In a separate terminal (or via systemd service), start the camera watcher
python3 face_recognition_module/face_watcher.py
```

### 3. Remote HTTPS Access (Tailscale Funnel)
To access the Raspberry Pi backend securely from anywhere over HTTPS and `wss://` WebSockets:
```bash
sudo tailscale funnel --bg 8000
```

---

## 📱 Flutter Mobile App Setup

### 1. Configure Backend URL
Update `smart_door_app/lib/config/api_config.dart` or pass `--dart-define`:
```bash
cd smart_door_app
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://your-pi-hostname.ts.net
```
*(If using Firebase Cloud Messaging, place your `google-services.json` in `smart_door_app/android/app/google-services.json` before building).*

---

## 🏗️ Tech Stack

| Layer | Technology |
|---|---|
| **Mobile App** | Flutter (Dart), Riverpod, GoRouter |
| **Backend API** | FastAPI (Python), SQLAlchemy, Uvicorn |
| **Database** | SQLite (`smart_door.db`) |
| **Real-Time Events** | WebSockets + Firebase Cloud Messaging (FCM) |
| **Computer Vision** | `Picamera2`, `dlib`, `face_recognition`, NumPy, Pillow |
| **Hardware Control** | `RPi.GPIO` (TIP122 Solenoid Driver + Push-Button/Buzzer Doorbell) |
| **Authentication** | JWT + `bcrypt` + Role-Based Invite Tokens |
