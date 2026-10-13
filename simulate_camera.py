import requests

API_URL = "http://localhost:8000"
TEST_IMAGE_PATH = r"C:\Users\NEO\.gemini\antigravity\brain\4b43e045-30c1-4a48-94ac-07f0365e297b\suspicious_stranger_1775996875686.png"

def simulate_alert():
    try:
        print("📸 Simulating unauthorized person at the door...")
        
        with open(TEST_IMAGE_PATH, "rb") as image_file:
            files = {"file": ("visitor.png", image_file, "image/png")}
            resp = requests.post(f"{API_URL}/alerts/from-camera", files=files)
            
        if resp.status_code == 200:
            print("✅ Alert successfully sent to backend!")
            print("📱 Check your Flutter app for the WebSocket notification!")
        else:
            print(f"❌ Failed to send alert. Status: {resp.status_code}")
            
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    simulate_alert()
