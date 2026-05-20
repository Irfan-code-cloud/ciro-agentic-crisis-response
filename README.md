# CIRO: Urban Agentic Crisis Response (CDA, Islamabad Edition)

CIRO (Crisis Intelligence & Response Orchestration) is an autonomous, multi-agent AI system developed specifically for the **Capital Development Authority (CDA), Islamabad**. By leveraging advanced agentic workflows and structured data processing, CIRO transforms urban emergency management, making real-time, high-stakes decisions to minimize response latency across the capital.

---

## 🔒 Secure Command Access
To ensure operational security, CIRO is protected by a multi-layered authentication portal. Only authorized CDA personnel can access the live intelligence dashboard, maintaining the integrity of emergency operations.

<img width="1366" height="633" alt="Login" src="https://github.com/user-attachments/assets/5db0f180-fe59-40ea-9c12-6d204bbcf50a" />

---

## ⚙️ The 3-Tier Architecture Pipeline
CIRO operates on a highly structured multi-agent workflow that handles crisis data from initial report to final execution:

1. **Ingestion (Intake Agent):** Real-time citizen complaints (via WhatsApp) and city signals are captured. The Intake Agent performs initial NLP-based triage to classify and validate the crisis against our core JSON data schemas.
2. **Commander (Core Agent):** The central intelligence hub. It analyzes severity, context, and historical precedents using Gemini models to determine the optimal emergency response strategy.
3. **Dispatch (Action Agent):** The system automatically executes the final command, triggering resource allocation, calculating routing protocols, and updating the live intelligence feed in Firebase so the mobile app reflects status changes instantly.

---

## 🗺️ Live Tactical Intelligence
The CIRO Command Center provides a real-time view of Islamabad’s urban landscape. Below, the system illustrates a **G-10 sector flash flood** scenario, showing active rerouting strategies and emergency zones.

<img width="1366" height="630" alt="Map" src="https://github.com/user-attachments/assets/ff44084b-cd7e-42b5-b30f-7b1ea19d310f" />
<img width="1366" height="629" alt="recommendation" src="https://github.com/user-attachments/assets/fce1ea05-dc23-48df-b710-5b7ed985319e" />

### Intelligence Mapping: How Rerouting Works
The CIRO dashboard features a tactical map powered by **Folium**. Our dispatch logic interacts with the map by:
* Dynamically updating coordinate markers based on incoming event data.
* Visualizing path optimizations for emergency vehicles navigating Islamabad’s road network.
* Injecting real-time route overlays directly into the map component to guide field personnel.

---

## 📡 Automated Emergency Communication
CIRO features a powerful **"Execute Communication"** module. When a crisis is confirmed, the AI does not just plan the response; it performs the outreach autonomously:

<img width="1366" height="642" alt="broadcast" src="https://github.com/user-attachments/assets/b7088b06-e58b-47ea-805a-730377ec496a" />

* **AI-Generated Content:** Upon clicking the "Execute Communication" button, the Commander Agent triggers specialized sub-agents to draft high-impact content.
* **Multi-Channel Orchestration:** The AI writes a platform-specific **Twitter post** for public awareness, an **emergency SMS** for field responders, and a **professional email** for CDA administration, all tailored to the specific nature of the event.

---

## 📊 Data Orchestration & Signal Injection
CIRO relies on a sophisticated architecture for handling city-wide data:
* **Signal Injection:** Through the "Inject Signal" interface, we can simulate complex scenarios (e.g., Flash Floods, Highway Pileups). Incoming signals are mapped against our JSON schemas, allowing agents to instantly parse and convert raw alerts into standardized formats required for agentic reasoning.
* **Citizen Complaint Registry:** Integrated with Firebase, this registry logs all incoming emergency reports for historical analysis and immediate task management.

<img width="1366" height="645" alt="signal" src="https://github.com/user-attachments/assets/6429edbf-bf1c-4ed1-b416-e2207fe30c49" />
<img width="1366" height="637" alt="registry" src="https://github.com/user-attachments/assets/f02d149d-ab1d-4b90-b0ce-9882a1cbf533" />

---

## 🛠 Tech Stack
* **Backend:** FastAPI (Python) for robust, high-performance API handling.
* **AI Orchestration:** Google Antigravity SDK and Vertex AI for advanced agentic decision-making.
* **Frontend:** Flutter for a cross-platform, high-performance mobile experience.
* **Database:** Firebase Firestore for real-time synchronization of the Crisis Registry.
* **Infrastructure:** Deployed on Google Cloud Run for seamless, scalable, and secure deployment.