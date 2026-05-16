import json
import google.auth
import uvicorn
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import vertexai
from vertexai.generative_models import GenerativeModel
from google.oauth2 import service_account

app = FastAPI(title="CIRO Backend")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- BULLETPROOF HYBRID AUTHENTICATION ---
try:
    key_path = "vertex-key.json"

    # Path 1: Irfan's Local Environment (Uses JSON file)
    if os.path.exists(key_path):
        print("🔑 Local JSON key found! Authenticating via Service Account...")
        credentials = service_account.Credentials.from_service_account_file(key_path)
        project_id = credentials.project_id
        vertexai.init(
            project=project_id, location="us-central1", credentials=credentials
        )

    # Path 2: Adan's Environment (Uses gcloud terminal login)
    else:
        print(
            "🌐 No local key found. Attempting gcloud Application Default Credentials..."
        )
        credentials, project_id = google.auth.default()
        vertexai.init(
            project=project_id, location="us-central1", credentials=credentials
        )

    model = GenerativeModel("gemini-2.5-flash")
    print("✅ Vertex AI Initialized successfully!")
except Exception as e:
    print(f"⚠️ CRITICAL AUTH ERROR: {e}")
    model = None

# --------------------------------


@app.get("/api/status")
def get_status():
    return {"status": "OPERATIONAL", "message": "Backend is live."}


@app.get("/api/analyze")
def run_ai_analysis(signal: str = None, lang: str = "en"):
    # The simulated noisy social media post from the user, or the dynamically injected signal
    tweet = (
        signal
        if signal
        else "G-10 mein pani bhar gaya hai, gaariyan phans gayi hain! Rescue needed."
    )

    # ---------------------------------------------------------
    # AGENT 1: Triage & Clustering
    # ---------------------------------------------------------
    prompt_agent1 = f"""
    Extract the 'Location' and 'Crisis_Type' from the following noisy social media post.
    Return ONLY a valid JSON object with exactly these two keys: 'Location' and 'Crisis_Type'.
    
    Post: {tweet}
    """

    # Default fallbacks
    location = "Sector G-10"
    crisis_type = "Severe Flooding"

    if model:
        try:
            response1 = model.generate_content(prompt_agent1)
            # Strip markdown formatting
            text1 = response1.text.strip()
            if text1.startswith("```json"):
                text1 = text1[7:]
            elif text1.startswith("```"):
                text1 = text1[3:]
            if text1.endswith("```"):
                text1 = text1[:-3]

            triage_data = json.loads(text1.strip())
            location = triage_data.get("Location", location)
            crisis_type = triage_data.get("Crisis_Type", crisis_type)
        except Exception as e:
            print(f"Agent 1 Vertex AI Error: {e}")

    print(f"🕵️ AGENT 1 (TRIAGE): Detected {crisis_type} at {location}")

    # ---------------------------------------------------------
    # AGENT 2: Context & Tooling (Simulated)
    # ---------------------------------------------------------
    def fetch_weather_and_traffic(loc):
        # Simulated API call pulling real-world constraints for the detected location
        return {
            "weather": "Severe Heavy Rainfall Alert",
            "traffic": "0 km/h Deadlock on primary arteries",
        }

    context_data = fetch_weather_and_traffic(location)
    print(
        f"📡 AGENT 2 (CONTEXT): Retrieved Weather and Traffic API data for {location}"
    )

    # ---------------------------------------------------------
    # AGENT 3: The Commander
    # ---------------------------------------------------------
    prompt_agent3 = f"""
    You are the City Administrator for Islamabad. Create a strategic response based on the following data.
    
    Crisis: {crisis_type}
    Location: {location}
    Weather Context: {context_data['weather']}
    Traffic Context: {context_data['traffic']}
    
    If lang is 'ur', you MUST translate the 'detected_situation', 'impact', and 'recommended_actions' arrays into professional Urdu. If 'en', use English. (Language: {lang})
    
    You MUST return ONLY a valid JSON object strictly formatted like this:
    {{
        "analysis": {{
            "crisis_type_short": "A 1-2 word string (e.g., COMMERCIAL FIRE)",
            "epicenter": {{"lat": 33.6667, "lng": 73.0167}},
            "detected_situation": "A clear, concise summary of the situation",
            "confidence": "High",
            "impact": ["Impact 1", "Impact 2"],
            "recommended_actions": ["Action 1", "Action 2", "Action 3"],
            "routing": {{
                "blocked_start": {{"lat": 33.6667, "lng": 73.0167}},
                "blocked_end": {{"lat": 33.6700, "lng": 73.0200}},
                "detour_start": {{"lat": 33.6600, "lng": 72.9500}},
                "detour_end": {{"lat": 33.6660, "lng": 73.0700}}
            }}
        }}
    }}
    """

    # Default fallback JSON ensuring the Flutter UI doesn't crash on failure
    commander_json = {
        "analysis": {
            "crisis_type_short": crisis_type.upper()[:15],
            "epicenter": {"lat": 33.6667, "lng": 73.0167},
            "detected_situation": f"{crisis_type} detected at {location} accompanied by {context_data['weather']}.",
            "confidence": "High",
            "impact": [
                "Vehicles trapped in deep water",
                f"Traffic deadlock ({context_data['traffic']})",
                "High risk of electrical hazards",
            ],
            "recommended_actions": [
                "Reroute traffic to Kashmir Highway",
                f"Dispatch high-clearance rescue teams to {location}",
                "Broadcast public safety alert",
            ],
            "routing": {
                "blocked_start": {"lat": 33.6667, "lng": 73.0167},
                "blocked_end": {"lat": 33.6700, "lng": 73.0200},
                "detour_start": {"lat": 33.6600, "lng": 72.9500},
                "detour_end": {"lat": 33.6660, "lng": 73.0700},
            },
        }
    }

    if model:
        try:
            response3 = model.generate_content(prompt_agent3)
            # Strip markdown formatting
            text3 = response3.text.strip()
            if text3.startswith("```json"):
                text3 = text3[7:]
            elif text3.startswith("```"):
                text3 = text3[3:]
            if text3.endswith("```"):
                text3 = text3[:-3]

            parsed_json = json.loads(text3.strip())
            if "analysis" in parsed_json:
                commander_json = parsed_json
            else:
                # Wrap it if the model forgot the root key
                commander_json = {"analysis": parsed_json}
        except Exception as e:
            print(f"Agent 3 Vertex AI Error: {e}")

    print("🧠 AGENT 3 (COMMANDER): Strategic response generated. Forwarding to UI.")

    return commander_json


if __name__ == "__main__":
    print("🚀 Starting CIRO Backend on Port 8000...")
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)
