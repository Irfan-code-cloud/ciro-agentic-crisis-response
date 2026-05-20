import json
import google.auth
import uvicorn
import os
import hashlib
from fastapi import FastAPI, Form, Response, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBasic, HTTPBasicCredentials
import secrets
import vertexai
from vertexai.generative_models import GenerativeModel
from google.oauth2 import service_account
from twilio.twiml.messaging_response import MessagingResponse
from backend.agents.citizen_intake_agent import process_citizen_report
from pydantic import BaseModel
from typing import List
import firebase_admin
from firebase_admin import credentials as fb_credentials, firestore
import os
from dotenv import load_dotenv

# Load environment variables from the .env file
load_dotenv()

class CrisisPayload(BaseModel):
    location: str
    crisis_type: str
    recommended_actions: List[str]

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

# --- FIREBASE FIRESTORE INITIALIZATION ---
try:
    # 1. Try local key file first (for testing on your laptop)
    if os.path.exists("firebase-key.json"):
        cred = fb_credentials.Certificate("firebase-key.json")
        if not firebase_admin._apps:
            firebase_admin.initialize_app(cred)
    # 2. If no key file, use Cloud Run's automatic credentials
    else:
        if not firebase_admin._apps:
            firebase_admin.initialize_app()
            
    db = firestore.client()
    print("🔥 Firebase Firestore connected successfully!")
except Exception as e:
    print(f"Firebase Init Error: {e}")
    db = None

# --------------------------------

# Global State (live_reports is now persisted on Firestore)

# Geospatial Anchoring Dictionary
SECTOR_COORDINATES = {
    "F-8": {"lat": 33.7150, "lng": 73.0450},
    "G-10": {"lat": 33.6760, "lng": 73.0130},
    "E-11": {"lat": 33.7020, "lng": 72.9750},
    "Kashmir Highway": {"lat": 33.6840, "lng": 73.0290}
}


# --- BASIC AUTHENTICATION ---
security = HTTPBasic()

def verify_cda_officer(credentials: HTTPBasicCredentials = Depends(security)):
    correct_username = secrets.compare_digest(credentials.username, "CDA_officer")
    
    # Securely fetch the expected password directly from the environment
    expected_password = os.getenv("COMMAND_CENTER_PASSWORD")
    
    # Failsafe: If the environment variable isn't set, deny access
    if not expected_password:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Server configuration error: Missing security credentials.",
        )
        
    correct_password = secrets.compare_digest(credentials.password, expected_password)
    
    if not (correct_username and correct_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username

@app.post("/api/whatsapp-webhook")
def whatsapp_webhook(Body: str = Form(""), MediaUrl0: str = Form(None)):
    print(f"📲 [WhatsApp Webhook] Received message: {Body}")
    if MediaUrl0:
        print(f"📸 [WhatsApp Webhook] Received media: {MediaUrl0}")
        
    # Process through the Intake Agent
    analysis = process_citizen_report(message_text=Body, media_url=MediaUrl0)
    
    # Store globally for Flutter UI to fetch later (using Firestore)
    if db is not None:
        try:
            db.collection("live_reports").add(analysis)
        except Exception as e:
            print(f"Firestore Add Error: {e}")
    else:
        print("⚠️ Firestore not initialized, report not saved.")
    
    resp = MessagingResponse()
    resp.message(analysis.get("citizen_reply", "We have received your report."))
    return Response(content=str(resp), media_type="application/xml")

@app.get("/api/live-reports", dependencies=[Depends(verify_cda_officer)])
def get_live_reports():
    if db is not None:
        try:
            reports_list = []
            for doc in db.collection("live_reports").stream():
                report = doc.to_dict()
                report["id"] = doc.id
                if "lat" not in report or "lng" not in report:
                    report["lat"] = 33.6938
                    report["lng"] = 73.0053
                reports_list.append(report)
            return reports_list
        except Exception as e:
            print(f"Firestore Get Error: {e}")
            return []
    return []

@app.delete("/api/live-reports/{doc_id}", dependencies=[Depends(verify_cda_officer)])
def delete_live_report(doc_id: str):
    if db is not None:
        try:
            db.collection("live_reports").document(doc_id).delete()
            return {"status": "success", "message": "Report deleted"}
        except Exception as e:
            print(f"Firestore Delete Error: {e}")
            return {"status": "error", "message": str(e)}
    return {"status": "error", "message": "Database not initialized"}

@app.delete("/api/live-reports/purge/all", dependencies=[Depends(verify_cda_officer)])
def purge_all_live_reports():
    if db is not None:
        try:
            docs = db.collection("live_reports").stream()
            for doc in docs:
                doc.reference.delete()
            return {"status": "success", "message": "Database purged"}
        except Exception as e:
            print(f"Firestore Purge Error: {e}")
            return {"status": "error", "message": str(e)}
    return {"status": "error", "message": "Database not initialized"}

@app.get("/api/status")
def get_status():
    return {"status": "OPERATIONAL", "message": "Backend is live."}

@app.post("/api/broadcast", dependencies=[Depends(verify_cda_officer)])
def execute_communications(payload: CrisisPayload):
    print(f"📡 [Broadcast Agent] Drafting communications for {payload.crisis_type} at {payload.location}")
    if not model:
        return {"error": "Vertex AI is not initialized."}
        
    prompt = f"""
    You are the Chief Communications Officer for the Capital Development Authority (CDA) in Islamabad.
    A crisis has occurred.
    Location: {payload.location}
    Crisis Type: {payload.crisis_type}
    Recommended Actions: {', '.join(payload.recommended_actions)}
    
    Draft three precise communications based on this data.
    
    CRITICAL LOCALIZATION RULES FOR URDU BROADCASTS:
    - You are a native Urdu-speaking Public Relations Officer for Islamabad's emergency services.
    - The `twitter_post` and `sms_alert` MUST be written in highly professional, natural-sounding, and grammatically flawless Urdu script (اردو).
    - NEVER use literal, robotic, or word-for-word translations from English. Use authoritative and urgent phrasing suitable for public safety announcements.
    - TRANSLITERATE ALL LOCATIONS: You MUST convert English sector names into Urdu script (e.g., 'F-8' MUST be written as 'ایف-8', 'G-10' MUST be 'جی-10', 'E-11' MUST be 'ای-11', 'Kashmir Highway' MUST be 'کشمیر ہائی وے').
    - Do NOT include any English alphabet characters in the Urdu fields.
    - CRITICAL: Do not include raw latitude or longitude numbers in the broadcast messages. Use descriptive location names (e.g., 'Srinagar Highway', 'F-8 Markaz') so the alerts are easily understood by the public.
    
    Tasks:
    1. twitter_post: An official, urgent X/Twitter update with relevant hashtags following the Urdu rules above.
    2. sms_alert: A localized public SMS warning following the Urdu rules above.
    3. internal_email: A formal, structured dispatch email to the Rescue/Fire Chief outlining the deployment strategy in English. The output MUST be strictly plain text. Do NOT use any Markdown formatting. Do NOT use asterisks (**) for bolding or any other special formatting characters.
    
    Output ONLY a valid JSON object matching this schema exactly (no markdown blocks, just raw JSON):
    {{
      "twitter_post": "...",
      "sms_alert": "...",
      "internal_email": "..."
    }}
    """
    
    try:
        response = model.generate_content(prompt)
        text = response.text.strip()
        
        if text.startswith("```json"):
            text = text[7:]
        elif text.startswith("```"):
            text = text[3:]
        if text.endswith("```"):
            text = text[:-3]
            
        comms_data = json.loads(text.strip())
        return comms_data
    except Exception as e:
        print(f"⚠️ [Broadcast Agent] Error: {e}")
        return {
            "twitter_post": "Emergency alert: Please avoid the affected area. CDA teams are responding.",
            "sms_alert": "CDA Alert: Mutasira ilaqay se door rahein. Rescue teams pohnch rahi hain.",
            "internal_email": "Subject: URGENT DISPATCH\\n\\nPlease deploy emergency units to the affected zone immediately."
        }


@app.get("/api/analyze", dependencies=[Depends(verify_cda_officer)])
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
    
    # Geographic Anchoring Logic
    base_lat = 33.6844 # Default Islamabad Center
    base_lng = 73.0479
    for sector, coords in SECTOR_COORDINATES.items():
        if sector.lower() in location.lower():
            base_lat = coords["lat"]
            base_lng = coords["lng"]
            break

    prompt_agent3 = f"""
    You are the City Administrator for Islamabad. Create a strategic response based on the following data.
    
    Crisis: {crisis_type}
    Location: {location}
    Weather Context: {context_data['weather']}
    Traffic Context: {context_data['traffic']}
    
    CRITICAL GEOGRAPHY INSTRUCTION: The crisis is located at {location}. The precise coordinates for this sector are Lat: {base_lat}, Lng: {base_lng}. ALL coordinates in your `routing` JSON object (`blocked_start`, `blocked_end`, `detour_start`, `detour_end`) MUST be mathematically generated to fall strictly within a 0.005 degree radius of these exact base coordinates. Do NOT use any coordinates from the formatting examples.
    
    CRITICAL ISLAMABAD STATISTICS FOR KPI CALCULATION:
    - Fire Brigade: CDA operates ~10 stations (HQ at G-7, branches at I-9, F-7) with approx 30 active fire tenders.
    - Ambulances: Rescue 1122, Edhi, and hospitals (PIMS, Polyclinic) have ~60 ready-to-deploy ambulances.
    - Police: ICT Police can deploy 10-15 mobile units per sector for rapid perimeter control.
    Calculate required units based strictly on these limits.
    
    If lang is 'ur', you MUST translate the 'detected_situation', 'impact', and 'recommended_actions' arrays into professional Urdu. If 'en', use English. (Language: {lang})
    CRITICAL: The `resource_kpis` array (both `label` and `reasoning`) MUST ALWAYS remain in English, regardless of the requested language, to ensure rapid processing.
    
    The `current_impacts` and `recommended_actions` MUST be strictly flat JSON arrays of short, clean strings (e.g., ["Deploy fire trucks", "Block Kashmir Highway"]). Absolutely NO markdown, NO bullet points, and NO numbering inside the array items.
    CRITICAL: One of your `recommended_actions` MUST explicitly explain the Active Reroute strategy. You must mention the detour path you generated and explain WHY it is necessary based on the traffic and weather context (e.g., 'Diverting traffic via Kashmir Highway to bypass 0km/h deadlock').
    CRITICAL: Never output raw latitude and longitude coordinates in your text responses. Always translate coordinates into human-readable locations, street names, or prominent landmarks based on the context provided.
    
    You MUST return ONLY a valid JSON object strictly formatted like this:
    {{
        "analysis": {{
            "crisis_type_short": "A 1-2 word string (e.g., COMMERCIAL FIRE)",
            "epicenter": {{"lat": 33.6667, "lng": 73.0167}}, // PLACEHOLDER: Must be replaced with base coordinates
            "detected_situation": "A clear, concise summary of the situation",
            "confidence": "High",
            "impact": ["Impact 1", "Impact 2"],
            "recommended_actions": ["Action 1", "Action 2", "Action 3"],
            "resource_kpis": [{{"label": "Fire Units", "value": 5, "reasoning": "Dispatched 5 tenders from G-7 and F-7 stations due to high commercial density and fire spread risk."}}],
            "routing": {{
                // PLACEHOLDERS: MUST be mathematically generated around base Lat: {base_lat}, Lng: {base_lng}
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
                f"Active Reroute: Diverting traffic via Kashmir Highway to bypass the deadlock at {location}.",
                f"Dispatch high-clearance rescue teams to {location}",
                "Broadcast public safety alert",
            ],
            "resource_kpis": [
                {"label": "Fire Units", "value": 2, "reasoning": "Standard response for localized incident."},
                {"label": "Ambulances", "value": 5, "reasoning": "Standard deployment based on moderate traffic deadlock."},
                {"label": "Police Units", "value": 3, "reasoning": "Perimeter control needed for electrical hazard."}
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
