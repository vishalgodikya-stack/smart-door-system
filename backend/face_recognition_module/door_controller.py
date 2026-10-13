"""
door_controller.py — GPIO door relay control utilities
Raspberry Pi 4 — BCM pin numbering
"""
import os
import time

DOOR_GPIO_PIN = int(os.getenv("DOOR_GPIO_PIN", 18))
UNLOCKED_DURATION = int(os.getenv("DOOR_UNLOCK_DURATION", 5))  # seconds

try:
    import RPi.GPIO as GPIO
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(DOOR_GPIO_PIN, GPIO.OUT)
    GPIO.output(DOOR_GPIO_PIN, GPIO.LOW)
    GPIO_AVAILABLE = True
except (ImportError, RuntimeError):
    GPIO_AVAILABLE = False
    print("[GPIO] Simulation mode — GPIO not available")


def unlock(duration_seconds: int = UNLOCKED_DURATION):
    """Unlock the door relay for a set number of seconds, then re-lock."""
    if GPIO_AVAILABLE:
        GPIO.output(DOOR_GPIO_PIN, GPIO.HIGH)
        print(f"[DOOR] Unlocked for {duration_seconds}s")
        time.sleep(duration_seconds)
        GPIO.output(DOOR_GPIO_PIN, GPIO.LOW)
        print("[DOOR] Locked")
    else:
        print(f"[DOOR SIM] Would unlock for {duration_seconds}s")


def lock():
    """Immediately lock the door."""
    if GPIO_AVAILABLE:
        GPIO.output(DOOR_GPIO_PIN, GPIO.LOW)
        print("[DOOR] Force locked")
    else:
        print("[DOOR SIM] Force locked")


def get_status() -> str:
    """Read current GPIO pin state."""
    if GPIO_AVAILABLE:
        state = GPIO.input(DOOR_GPIO_PIN)
        return "unlocked" if state == GPIO.HIGH else "locked"
    return "simulation"


def cleanup():
    if GPIO_AVAILABLE:
        GPIO.cleanup()
