# IFSO Location Request Management System

## Overview

The **IFSO Location Request Management System** is a secure, forensic-grade solution designed to automate authorized law-enforcement mobile location requests via carrier SMS. It replaces error-prone manual copy-and-send workflows with an auditable mobile application and backend service.

Field Officers submit location requests specifying target numbers and carrier profiles. An Investigating Officer (IO) reviews pending requests and triggers execution from an enterprise-managed (MDM) Android device containing an authorized carrier SIM. Incoming carrier replies are intercepted, parsed, and logged with strict chain-of-custody controls.

---

## Current Status

```text
Phase 1 completed.
Phase 2 not yet implemented.
```

- **Current Version:** `0.1.0` (Phase 1 — Foundation & Architecture)
- **Next Target:** Phase 2 — Officer Request Management (Request creation forms, server-side storage, tokenized single-use links).

---

## Technology Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Backend Framework** | FastAPI (Python 3.12+) | High-performance asynchronous REST API |
| **Data Validation** | Pydantic v2 / Pydantic Settings | Strictly typed schemas and environment configuration |
| **Database** | MongoDB (via Motor async driver) | Document store for requests, carrier profiles, and audit trails |
| **Mobile App** | Flutter / Dart (Material 3) | Cross-platform UI for Field Officers and IO review |
| **Platform Telephony** | Android Native (Kotlin / SmsManager) | Hardware-bound SMS transmission from authorized SIM (Phase 3) |
| **Testing** | Pytest / Pytest-Asyncio / Flutter Test | Automated unit, schema, and lifecycle verification |

---

## Repository Structure

```text
Automated_SIM_Location/
├── backend/
│   ├── app/
│   │   ├── core/           # Configuration, logging, database, and exceptions
│   │   ├── models/         # MongoDB document models and lifecycle enums
│   │   ├── schemas/        # Pydantic v2 request/response schemas
│   │   ├── services/       # Base service abstractions
│   │   ├── routes/         # API routers (health, requests, operators)
│   │   └── main.py         # FastAPI application entrypoint & lifespan
│   ├── tests/              # Pytest test suite (17 tests)
│   ├── requirements.txt    # Python dependencies
│   ├── pytest.ini          # Test runner configuration
│   └── .env.example        # Environment variable template
│
├── mobile_app/
│   ├── lib/
│   │   ├── core/
│   │   │   ├── constants/  # RequestState enum and accessibility helpers
│   │   │   └── theme/      # Centralized ThemeData, ColorScheme, Spacing, Radius, Typography
│   │   ├── screens/        # HomeScreen application shell
│   │   └── main.dart       # Flutter application entrypoint
│   ├── test/               # Flutter unit and widget tests
│   ├── android/            # Android platform configuration and manifest
│   ├── pubspec.yaml        # Flutter dependencies
│   └── analysis_options.yaml
│
├── docs/                   # Documentation and specifications index
├── Markdown_Files/         # Source of truth project documentation (PRD, Architecture, Design, etc.)
├── Markdown/Memory/        # Development session history (memory1.md)
├── .gitignore              # Multi-tier git exclusion rules
├── .env.example            # Root environment template
├── CHANGELOG.md            # Detailed version log
└── README.md               # Project documentation
```

---

## Phase 1 Implementation Summary

Phase 1 established the clean, secure, and maintainable foundation for the system:

1. **Monorepo Architecture:** Clean structural separation between backend, mobile client, documentation, and tests.
2. **FastAPI Backend:**
   - Lifespan application startup/teardown.
   - Structured JSON logging with automated redaction of phone numbers, passwords, credentials, coordinates, and raw SMS bodies.
   - Centralized exception handling mapping domain errors to standardized JSON envelopes.
   - System health endpoints (`/` and `/api/v1/health`) and OpenAPI interactive documentation (`/docs`).
3. **MongoDB Data Foundation:**
   - Asynchronous `DatabaseManager` using Motor with connection pooling.
   - Safe degraded offline handling: if MongoDB is unreachable locally, the backend starts gracefully and reports `degraded` health without crashing.
   - Document models for `location_requests`, `operators`, and `audit_logs`.
4. **Lifecycle State Machine:**
   - Enum with 8 distinct states: `CREATED`, `PENDING_IO_REVIEW`, `EXECUTING`, `WAITING_RESPONSE`, `COMPLETED`, `SMS_FAILED`, `TIMEOUT`, `RESPONSE_INVALID`.
   - Strict transition validation preventing illegal jumps.
5. **Data Privacy & Forensic Schemas:**
   - Automatic phone number masking (`+91 XXXXXX1234`) ensuring middle digits are redacted across UI displays and logs.
   - SHA-256 non-reversible hashing for query deduplication.
   - Request creation validation supporting 10-digit mobile numbers with country prefix normalization.
6. **API Conventions:**
   - Prepared route structure for `/api/v1/requests` (POST, GET, execute, result) returning 501 Not Implemented pending Phase 2/3.
   - Operator listing endpoint `/api/v1/operators` returning synthetic development carrier profiles.
7. **Flutter Application Foundation:**
   - Material 3 enabled application with light-first neutral theme.
   - Centralized design tokens per `Design.md`: `AppColors`, `AppSpacing` (8-point system), `AppRadius`, `AppTypography` (Inter + Monospace).
   - `HomeScreen` application shell with system status indicators, workflow cards, and lifecycle badge showcase.
   - Android telephony permission declarations for MDM-managed deployment.

---

## Setup & Development Guide

### 1. Backend Setup

#### Prerequisites
- Python 3.12+ (or Python 3.10+)
- `uv` or `pip`

#### Installation & Virtual Environment
```bash
# Navigate to backend directory
cd backend

# Create virtual environment
python -m venv .venv
# Or using uv:
uv venv .venv

# Activate virtual environment (Windows PowerShell)
.venv\Scripts\Activate.ps1

# Install dependencies
pip install -r requirements.txt
# Or using uv:
uv pip install -r requirements.txt
```

#### Environment Configuration
```bash
# Copy environment template
cp .env.example .env
```

Ensure the following variables are configured in `.env`:
```text
APP_ENV=development
APP_NAME=IFSO Location Request Management System
APP_DEBUG=true
LOG_LEVEL=INFO
MONGODB_URI=mongodb://localhost:27017
MONGODB_DATABASE=ifso_location_dev
API_V1_PREFIX=/api/v1
SECRET_KEY=insecure-dev-key-change-in-production-only-for-local-testing
```

#### Running the Backend Server
```bash
uvicorn backend.app.main:app --reload --host 0.0.0.0 --port 8000
```
- Root Health Status: `http://localhost:8000/`
- API Health Status: `http://localhost:8000/api/v1/health`
- OpenAPI Documentation: `http://localhost:8000/docs`

---

### 2. Running Backend Tests

The backend test suite verifies application startup, OpenAPI schema generation, lifecycle state transitions, Pydantic schema validation, phone masking, logging redaction, and database offline resilience:

```bash
# From repository root
backend\.venv\Scripts\python.exe -m pytest -v backend/tests
```

**Results:** `17 passed in ~1.1s`

---

### 3. Mobile App Setup (Flutter)

#### Prerequisites
- Flutter SDK (3.16.0 or higher)

#### Setup & Execution
```bash
cd mobile_app
flutter pub get
flutter analyze
flutter test
flutter run
```

---

## Security & Compliance Rules

The project strictly follows the forensic, legal, and operational rules defined in `Rules.md`:

1. **No Credentials in Version Control:** Never commit `.env` or sensitive credentials to Git.
2. **Synthetic Data Only:** Real phone numbers, subscriber identities, coordinates, or carrier credentials must NEVER be used in code, tests, or development environments.
3. **Forensic Evidence Preservation:** Raw carrier SMS replies are stored with SHA-256 integrity hashes and never altered.
4. **Hardware SIM Boundary:** SMS messages are NEVER sent from the backend or through third-party SMS gateways. The SMS MUST originate from the IO's corporate MDM-managed device and SIM.
5. **No Third-Party Scraping:** WhatsApp or third-party messaging apps are never scraped or accessed.
6. **No Android Policy Bypasses:** The application relies on standard Android enterprise APIs (`SmsManager`) and corporate MDM device-owner policies; it never uses root or security exploits.
7. **Sensitive Data Masking:** Phone numbers and geographic coordinates are masked in logs and standard UI screens.