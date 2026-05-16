import json
import os
import vertexai
from vertexai.generative_models import GenerativeModel
from dotenv import load_dotenv


# 1. Load and Verify Credentials
print("🔍 Checking Environment Variables...")
load_dotenv()
cred_path = os.getenv("GOOGLE_APPLICATION_CREDENTIALS")

if cred_path:
    print(f"🔑 Using local Service Account Key: {cred_path}")
else:
    print("🌐 No local key found. Defaulting to Google Cloud CLI (ADC) login...")

# 2. Initialize Vertex AI
print("⚙️ Initializing Vertex AI...")
# Calling init() without arguments tells the SDK to figure it out automatically
vertexai.init(location="us-central1")
model = GenerativeModel("gemini-2.5-flash")
print("✅ Vertex AI Initialized.")


def load_json(filename):
    current_dir = os.path.dirname(__file__)
    filepath = os.path.join(current_dir, "..", "mock_data", filename)
    with open(filepath, "r") as f:
        return json.load(f)


def analyze_signals():
    print("\n🧠 Fusion Agent: Gathering mock data...")
    try:
        fused_data = {
            "social": load_json("social_feed.json"),
            "weather": load_json("weather_api.json"),
            "traffic": load_json("traffic_api.json"),
        }
        print("✅ Data successfully loaded.")
    except Exception as e:
        print(f"❌ Data Error: {e}")
        return {"status": "ERROR", "message": f"Data load failed: {str(e)}"}

    prompt = f"""
    You are CIRO, a Crisis Intelligence Orchestrator. 
    Analyze the following real-time data streams: {json.dumps(fused_data)}
    
    Based on the signals, detect the emerging crisis. 
    Respond ONLY with a raw JSON object (no markdown, no backticks) using this exact structure:
    {{
        "detected_situation": "String describing the crisis and location",
        "confidence": "High, Medium, or Low",
        "impact": ["List", "of", "current", "impacts"],
        "recommended_actions": ["List", "of", "actions"]
    }}
    """

    print("📡 Sending request to Vertex AI... (If it hangs, it happens here!)")
    try:
        response = model.generate_content(prompt)
        print("✅ Received response from Vertex AI!")

        clean_text = response.text.replace("```json", "").replace("```", "").strip()
        analysis = json.loads(clean_text)
        return {"status": "SUCCESS", "analysis": analysis}
    except Exception as e:
        print(f"❌ Vertex AI Error: {e}")
        return {"status": "ERROR", "message": str(e)}
