import requests
import os

# The local IP of the backend
BACKEND_URL = "http://127.0.0.1:8000/alerts/from-camera"

def simulate_alert():
    # Create a dummy image file for testing
    dummy_file = "test_visitor.jpg"
    with open(dummy_file, "wb") as f:
        f.write(b"fake image data")

    print(f"Sending simulated camera alert to {BACKEND_URL}...")
    
    with open(dummy_file, "rb") as f:
        files = {'file': (dummy_file, f, 'image/jpeg')}
        try:
            response = requests.post(BACKEND_URL, files=files)
            if response.status_code == 200:
                print("✅ Success! Alert sent.")
                print("Response:", response.json())
                print("\nCHECK YOUR PHONE NOW! 🔔")
            else:
                print(f"❌ Failed with status code: {response.status_code}")
                print(response.text)
        except Exception as e:
            print(f"❌ Connection Error: {e}")
        finally:
            # Clean up dummy file
            if os.path.exists(dummy_file):
                os.remove(dummy_file)

if __name__ == "__main__":
    simulate_alert()
