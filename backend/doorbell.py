"""
doorbell.py — Local Push-Button and Buzzer controller
Hardware:
- Push-Button: GPIO 23 (Physical Pin 16) with internal pull-up (connected to GND at Pin 14)
- Active Buzzer: GPIO 24 (Physical Pin 18) with GND at Pin 20
Behavior:
- Button Pressed  -> Buzzer ON
- Button Released -> Buzzer OFF
"""
import os
import threading
import time

BUTTON_PIN = int(os.getenv("DOORBELL_BUTTON_PIN", 23))
BUZZER_PIN = int(os.getenv("DOORBELL_BUZZER_PIN", 24))

_thread = None
_stop_event = threading.Event()
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


def _doorbell_loop():
    """Background polling loop for button state."""
    while not _stop_event.is_set():
        if GPIO_AVAILABLE:
            try:
                # Active LOW: 0 when pressed, 1 when released
                is_pressed = (GPIO.input(BUTTON_PIN) == GPIO.LOW)
                GPIO.output(BUZZER_PIN, GPIO.HIGH if is_pressed else GPIO.LOW)
            except Exception as e:
                print(f"[DOORBELL] Polling error: {e}")
        time.sleep(0.02)  # 20ms polling interval for instant response and low CPU


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
