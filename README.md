# 🚀 CIRO Project: Local Setup Guide for Adan

Welcome to the **CIRO (Crisis Intelligence Orchestrator)** repository! 

This guide is specifically written to help you get the entire Multi-Agent architecture (Flutter frontend + FastAPI/Vertex AI backend) running flawlessly on your local machine in under 5 minutes. 

Because we are using enterprise-grade Google Cloud security, **you do not need to download any secret `.env` or `.json` API keys.** Your local environment will securely authenticate using your Google account.

---

## 🛠️ Prerequisites
Before starting, ensure you have these installed on your laptop:
1. **Python (3.10+)**
2. **Flutter SDK** (Stable channel)
3. **Google Cloud CLI (`gcloud`)** - *Crucial for securely connecting to the AI without a key file.*

---

## 📥 Step 1: Clone the Repository
Open your terminal, choose where you want the project to live, and pull down the latest code:
```bash
git clone [https://github.com/MuhammadEbad12/ciro_project.git](https://github.com/MuhammadEbad12/ciro_project.git)
cd ciro_project
```

## 🔐 Step 2: Authenticate Google Cloud (The Magic Step)

Instead of passing vulnerable API keys back and forth, we are using Application Default Credentials (ADC). Irfan has already authorized your Google account via GCP IAM.

Run this command in your terminal:

```bash
gcloud auth application-default login
```
A browser window will pop up. Simply log in with your authorized Google account, click allow, and close the window.

## 🐍 Step 3: Start the Python AI Backend

Keep your terminal open and navigate to the backend folder to set up the AI orchestrator:

```bash
cd backend

# 1. Create a fresh virtual environment
python -m venv venv

# 2. Activate the virtual environment
# -> On Windows:
.\venv\Scripts\activate
# -> On Mac/Linux:
# source venv/bin/activate

# 3. Install the required Python packages
pip install -r requirements.txt

# 4. Run the Uvicorn server
python main.py
```
Wait until you see ✅ Vertex AI Initialized successfully! and the server is running on http://127.0.0.1:8000.

## 📱 Step 4: Start the Flutter Dashboard

Open a **new, separate terminal window** (leave the backend server running in the first one), and launch the user interface:

```bash
# Make sure you are in the main project folder, then go to the frontend
cd ciro_frontend

# 1. Download all Flutter ecosystem packages
flutter pub get

# 2. Launch the interactive dashboard in your browser
flutter run -d chrome
```

