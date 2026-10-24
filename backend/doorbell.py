"""
doorbell.py — Local Push-Button and Buzzer controller with visitor photo alerts
Hardware:
- Push-Button: GPIO 23 (Physical Pin 16) with internal pull-up (connected to GND at Pin 14)
- Active Buzzer: GPIO 24 (Physical Pin 18) with GND at Pin 20
Behavior:
- Button Pressed  -> Buzzer ON
- Button Released -> Buzzer OFF
- Button Pressed (cooldown 15s) -> Captures camera photo, logs pending alert, broadcasts WebSocket, sends FCM notification with photo
"""
import asyncio
import os
import shutil
import threading
import time
import uuid

BUTTON_PIN = int(os.getenv("DOORBELL_BUTTON_PIN", 23))
BUZZER_PIN = int(os.getenv("DOORBELL_BUZZER_PIN", 24))
ALERT_COOLDOWN = 15.0  # seconds between photo alert notifications

_thread = None
_stop_event = threading.Event()
_last_alert_time = 0.0
_was_pressed = False
GPIO_AVAILABLE = False

try:
    import RPi.GPIO as GPIO
    GPIO.setwarnings(False)
    GPIO.setmode(GPIO.BCM)
    # Button input with internal pull-up (pressed = LOW, released = HIGH)
    GPIO.setup(BUTTON_PIN, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    # Buzzer output (active HIGH)
    GPIO.setup(BUZZER_PIN, GPIO.OUT, initial=GPIO.LOW)
    GPIO_AVAILABLE = True
    print(f"[DOORBELL] Initialized Button on GPIO {BUTTON_PIN} and Buzzer on GPIO {BUZZER_PIN}")
except (ImportError, RuntimeError) as e:
    print(f"[DOORBELL] RPi.GPIO not available ({e}) — running in simulation mode")


def _trigger_doorbell_alert():
    """Captures camera photo, logs pending alert, broadcasts over WebSockets, and sends FCM push notification."""
    try:
        from database import SessionLocal, Alert
        from websocket_manager import manager

        images_dir = os.getenv("IMAGES_DIR", "./images")
        os.makedirs(images_dir, exist_ok=True)

        filename = f"visitor_doorbell_{uuid.uuid4().hex[:10]}.jpg"
        filepath = os.path.join(images_dir, filename)

        shm_frame = "/dev/shm/latest_frame.jpg"
        if os.path.exists(shm_frame) and os.path.getsize(shm_frame) > 0:
            shutil.copy2(shm_frame, filepath)
        else:
            from PIL import Image
            img = Image.new("RGB", (640, 480), color=(50, 50, 70))
            img.save(filepath)

        db = SessionLocal()
        try:
            alert = Alert(image_path=filepath, status="pending")
            db.add(alert)
            db.commit()
            db.refresh(alert)

            base_url = os.getenv("BASE_URL", "http://localhost:8000")
            image_url = f"{base_url}/images/{filename}"

            out_dict = {
                "id": alert.id,
                "image_url": image_url,
                "status": "pending",
                "decided_by_name": None,
                "decision_at": None,
                "created_at": alert.created_at.isoformat(),
            }

            # Broadcast via WebSocket
            try:
                loop = None
                try:
                    loop = asyncio.get_running_loop()
                except RuntimeError:
                    pass

                if loop and loop.is_running():
                    asyncio.run_coroutine_threadsafe(manager.broadcast("new_alert", out_dict), loop)
                else:
                    asyncio.run(manager.broadcast("new_alert", out_dict))
            except Exception as e:
                print(f"[DOORBELL] WebSocket broadcast error: {e}")

            # Send FCM Push Notification
            try:
                from routers.alerts_router import send_push_notification
                title = "🔔 Someone at the Door"
                body = "Doorbell ring — tap to allow or deny entry."
                data = {
                    "alert_id": str(alert.id),
                    "type": "new_alert",
                    "image_url": image_url,
                }
                asyncio.run(send_push_notification(db, title, body, data=data, image_url=image_url))
            except Exception as e:
                print(f"[DOORBELL] Push notification error: {e}")

            print(f"[DOORBELL] Alert #{alert.id} generated successfully with photo: {filename}")
        finally:
            db.close()
    except Exception as e:
        print(f"[DOORBELL] Error in alert generation worker: {e}")


def _doorbell_loop():
    """Background polling loop for button state."""
    global _last_alert_time, _was_pressed
    while not _stop_event.is_set():
        if GPIO_AVAILABLE:
            try:
                # Active LOW: 0 when pressed, 1 when released
                is_pressed = (GPIO.input(BUTTON_PIN) == GPIO.LOW)
                GPIO.output(BUZZER_PIN, GPIO.HIGH if is_pressed else GPIO.LOW)

                # Detect rising edge (button just pushed)
                if is_pressed and not _was_pressed:
                    now = time.time()
                    if now - _last_alert_time >= ALERT_COOLDOWN:
                        _last_alert_time = now
                        print("[DOORBELL] Button pressed — triggering photo capture & notification...")
                        threading.Thread(target=_trigger_doorbell_alert, daemon=True, name="DoorbellAlertWorker").start()
                    else:
                        print(f"[DOORBELL] Button pressed (cooldown active: {int(ALERT_COOLDOWN - (now - _last_alert_time))}s remaining)")

                _was_pressed = is_pressed
            except Exception as e:
                print(f"[DOORBELL] Polling error: {e}")
        time.sleep(0.02)  # 20ms polling interval


def start_doorbell():
    """Start the doorbell listener thread."""
    global _thread
    if _thread is not None and _thread.is_alive():
        return
    _stop_event.clear()
    _thread = threading.Thread(target=_doorbell_loop, daemon=True, name="DoorbellWorker")
    _thread.start()
    print("[DOORBELL] Background listener started")


def stop_doorbell():
    """Stop the doorbell listener thread and turn off buzzer."""
    _stop_event.set()
    if GPIO_AVAILABLE:
        try:
            GPIO.output(BUZZER_PIN, GPIO.LOW)
        except Exception:
            pass
    print("[DOORBELL] Background listener stopped")
