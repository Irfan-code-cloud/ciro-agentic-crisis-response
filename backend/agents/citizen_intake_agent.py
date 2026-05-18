import json
import requests
from vertexai.generative_models import GenerativeModel, Part


def process_citizen_report(message_text: str, media_url: str = None) -> dict:
    # MOVE THE MODEL INITIALIZATION INSIDE THE FUNCTION HERE:
    model = GenerativeModel("gemini-2.5-flash")

    parts = []

    if media_url:
        try:
            # Download the image from Twilio's public URL
            response = requests.get(media_url, timeout=10)
            if response.status_code == 200:
                image_bytes = response.content
                # Use application/octet-stream if exact MIME type is unknown, but image/jpeg is standard for WhatsApp images
                parts.append(Part.from_data(image_bytes, mime_type="image/jpeg"))
        except Exception as e:
            print(f"⚠️ Warning: Could not process media_url {media_url}: {e}")

    prompt = """
You are an expert 911/CDA emergency dispatcher for the Capital Development Authority (CDA) in Islamabad, Pakistan.
Analyze the incoming citizen report. The citizen may be distressed, using English, Roman Urdu, or Urdu script.
If an image is provided, use it to assess the situation alongside the text.

Your Tasks:
1. Extract the crisis location (e.g., F-8 Markaz, G-10, Kashmir Highway). If unknown, say "Unknown".
2. Identify the crisis type (e.g., Fire, Flood, Accident, Pileup, Power Outage).
3. Assess the severity (High, Medium, Low).
4. Detect the citizen's language (English, Roman Urdu, or Urdu script).
5. Generate a short, reassuring response in the EXACT same language/script the citizen used. Tell them their report is logged and help/CDA teams are being notified.
6. Generate a concise English summary of the crisis for the tactical dashboard.

Output ONLY a valid JSON object matching this schema exactly (no markdown blocks, no backticks, just raw JSON text):
{
  "location": "Extracted location",
  "crisis_type": "Crisis type",
  "severity": "High/Medium/Low",
  "citizen_reply": "Comforting reply in citizen's original language",
  "translated_summary": "English summary"
}
"""

    parts.append(prompt)
    parts.append(f"Incoming Report from Citizen:\n{message_text}")

    try:
        print("🤖 [Intake Agent] Sending data to Gemini 2.5 Flash...")
        response = model.generate_content(parts)
        text = response.text.strip()

        # Strip markdown formatting just in case
        if text.startswith("```json"):
            text = text[7:]
        elif text.startswith("```"):
            text = text[3:]
        if text.endswith("```"):
            text = text[:-3]

        parsed_json = json.loads(text.strip())
        print("✅ [Intake Agent] Successfully parsed citizen report.")
        return parsed_json
    except Exception as e:
        print(f"⚠️ [Intake Agent] Vertex AI Error: {e}")
        # Fallback JSON to prevent server crash
        return {
            "location": "Unknown",
            "crisis_type": "General Emergency",
            "severity": "Medium",
            "citizen_reply": "Message received. The CDA is investigating the situation. / پیغام موصول ہو گیا ہے۔ سی ڈی اے صورتحال کا جائزہ لے رہا ہے۔",
            "translated_summary": f"Fallback summary: {message_text[:100]}",
        }
