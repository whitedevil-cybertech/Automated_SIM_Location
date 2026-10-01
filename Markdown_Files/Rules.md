# Development Rules (Location Request Management System)

**Executive Summary:** This document defines secure, forensic- and legal‐safe development rules for the Location Request Management app. The core principle is to maintain **evidence integrity and data privacy** while automating the authorized SMS location query workflow. We list allowed capabilities (the 10–15 day MVP scope and near-term features) and forbidden practices. We specify approved tech (Python, FastAPI, MongoDB, Flutter/Kotlin, Android SMS APIs, etc.) and error‐handling/audit requirements to ensure operational reliability. Finally, we impose strict AI/code guidelines (no legal advice, no unattended evidence decisions) and repository standards (branching, secrets, CI, MDM-only deployment).  

## 1. Core Principle  
- **Forensic Integrity:** All interactions with evidence (target phone numbers, SMS responses, timestamps) must preserve the original data without modification. Every request and response is treated as potential evidence.  Follow “write once” and chain-of-custody practices: do not alter or delete original logs, and record all actions in audit logs.  
- **Legal Compliance:** Assume each location request is made under legal authority. The system must not itself make or allow unauthorized location queries. Enforce that only authenticated IOs can initiate queries, and log approvals. Handle personal data (phone numbers, locations) securely. In many jurisdictions (e.g. India) access to location data is tightly regulated; treat location and subscriber data as *sensitive personal data* and apply industry best practices (encryption, access controls, minimal retention).  
- **Security & Privacy:** Follow least-privilege: the app should only request the minimum necessary permissions (SMS send/receive on the IO device). Protect data-in-transit (use HTTPS/TLS for all API calls). Encrypt sensitive fields (target numbers, responses) at rest (e.g. MongoDB encrypted storage) or via field-level encryption. Use strong authentication for officer/IO accounts (assume future JWT or OAuth), but defer full auth implementation until after MVP (we can assume internal sign-in or VPN access). All design decisions should prioritize secure handling of location data – e.g. mask phone numbers in UI (show only last 4 digits) once verified, and automatically purge logs after a legally-allowed period.  

## 2. Allowed Capabilities (MVP & Near-Term)  
These features **may** be implemented in the 10–15 day MVP and expanded later:  
- **Officer Request Creation:** Officers can input a target phone number (and metadata: case ID, operator, remarks) into the app. Provide a form and client-side validation (e.g. ensure numeric, required country prefix if needed). For example:  
  ```dart
  if (!RegExp(r'^\d{10,}$').hasMatch(number)) throw ValidationError("Enter a valid phone number");
  ```  
  Store only the normalized number (e.g. with country code) in the backend.  
- **Secure Shareable Links:** When an officer creates a request, the system generates a random, single-use link or token (e.g. UUID or 128-bit token) that the IO can use to access the request. **Do not** embed the phone number or case in the URL. For instance: `https://server.example/r/8f73a91c...`. The link identifies the request by a reference, not by exposing data. Include an expiration (e.g. 24h) and one-time-use logic.  
- **Operator-Profile Normalization:** Officers must select the telecom operator (Jio, Airtel, etc.). Use a configuration (operator profiles) on the backend to define each operator’s SMS formatting rules and destination number. *Do not hardcode logic for prefixes or numbers in code*. For example:  
  ```python
  operator = operator_profiles[request.operator]
  sms_number = operator.service_number  # e.g. "1900..." or short code
  text = operator.sms_template.format(number=normalized_number)
  ```  
  This makes it easy to update provider info without code changes.  
- **IO-Initiated SMS via SmsManager:** Only the IO device (signed-in as an IO user) may actually send the SMS. The app must use Android’s `SmsManager` API to send the text from the device’s SIM. For example (in Kotlin):  
  ```kotlin
  val sms = SmsManager.getDefault()
  sms.sendTextMessage(
      destinationAddress = "12345",  // operator’s number 
      scAddress = null,
      text = "LOCATE 91$targetNumber", 
      sentIntent = sentPI, deliveryIntent = null
  )
  ```  
  Note: **android.permission.SEND_SMS** is a *dangerous, hard-restricted* permission that requires the device to be corporate-managed and the app allowlisted by device policy. We assume an MDM/Device-Owner scenario for deployment, not public Play Store.  
- **SMS Reception & Raw Preservation:** The IO app must also receive the SMS reply. Use `BroadcastReceiver` (with **android.permission.RECEIVE_SMS**) to catch incoming SMS and correlate it to the pending request (e.g. match sender number or use an SMS ID). Always preserve the *raw SMS text* in the database for auditing; then parse out location data from it if needed. For example, on receive:  
  ```kotlin
  override fun onReceive(context: Context, intent: Intent) {
      val bundle = intent.extras
      // ... extract SMS text ...
      backendClient.submitSmsResponse(requestId, rawText)
  }
  ```  
  Mark the request state as “Completed” only after logging the raw response.  
- **Audit Logging & State Machine:** Every action (create request, view request, initiate SMS, SMS sent status, SMS received) must be recorded in a tamper-evident log. Implement a clear state machine for a request: e.g. `CREATED -> PENDING_IO -> EXECUTING -> WAITING_RESPONSE -> COMPLETED/FAILED`. Transition rules and timestamps should be logged so any gap (e.g. no SMS reply for X minutes) can trigger alerts or timeouts.  
- **Role-Based Access:** Begin with two roles: Officer and IO. Officers can create requests, IOs can execute them. In MVP assume separate login or selection of role. Ensure an officer *cannot* send SMS directly – only an authorized IO may do so via their device. (We assume an IO signs in on their own device.)  
- **Temporary Data Minimization:** For now store phone numbers and SMS content in the database, but tag them as “sensitive”. They should be encrypted or masked in logs, and possibly scrubbed after a case is closed or after a retention period. At minimum, store checksums or last-4-digits for quick UI display, never expose full numbers in link URLs or logs.

## 3. Forbidden Practices  
These practices are strictly disallowed:  
- **No Plaintext Storage of Sensitive Data:** Do **not** store raw target numbers or location coordinates in plaintext logs, URLs, or client-side. Always encrypt or hash sensitive fields (e.g. store only SHA-256 of the phone number for deduplication, and/or encrypt at rest with a key). For example, use MongoDB’s encrypted field or an application-layer cryptography library (e.g. Python `cryptography` or MongoDB Field-Level Encryption). Never log the SMS content unencrypted.  
- **No Backend-Originated SMS/Impersonation:** The SMS must originate from the IO’s authorized SIM. **Do not** program the backend to send SMS (e.g. via an SMS gateway) pretending to be the IO. That would breach the telecom’s authentication rules and law enforcement chain-of-custody. The app’s SMS sending must go through the device’s telephony stack (via `SmsManager`).  
- **No WhatsApp or Third-Party Scraping:** Do not attempt to read WhatsApp or other messaging apps to auto-import numbers. It’s both technically infeasible (WhatsApp encrypts messages) and likely illegal (violates user privacy and terms of service). All input must come from officers manually entering data or from approved sources.  
- **No Unapproved Play Store Deployment:** Given the SMS permissions needed, **do not** publish this app on Google Play as-is. Play Store policy heavily restricts SMS/MMS permissions unless the app is the user’s default SMS app or granted special exception. Assume distribution via a managed (MDM) channel only. If Play Store is ever needed, first get formal permission from Google/Meta as a recognized law-enforcement app – but that is beyond the MVP.  
- **No Hardcoding Credentials or Numbers:** Telecom service numbers, API keys, or passwords should not be hardcoded in source. Put operator service numbers and SMS templates in a configuration file or database (e.g. `operator_profiles.yml`). Secrets (like any auth tokens or DB passwords) must be in environment variables or a secure secrets manager, not in code or repository.  
- **No Sensitive Data in URLs/Logs:** Do not pass the target number or detailed location in query parameters, short link tokens, or human-readable URLs. For example, **do not** do `GET /request?number=9876543210`. Always use opaque identifiers (UUIDs or random tokens) for requests. Likewise, do not log outgoing SMS contents on the client console or share them in any channel.  
- **No Bypass of Device Policies:** We assume the phones will be corporate-managed (e.g. with a Device Owner or Work Profile) so SMS permissions can be allowlisted. Under **no circumstances** should the app attempt to bypass Android’s security model (e.g. via root, exploits, or requesting unrestricted use of SMS). Do not require users to disable Play Protect or remove device management.  
- **No Self-Executing Commands:** This is a static-analysis-first tool. Avoid any features that automatically execute or decode the SMS response without IO review. Parsing of the SMS is allowed for display, but the IO must confirm it before sharing. Do not design the app to, for example, auto-trigger a triangulation process or access GPS on the target (those are handled by the telecom, not this app).  

## 4. Approved Libraries & Tools  
Use only these vetted technologies to ensure maintainability and security:  

- **Backend:** Python 3.9+ with [FastAPI](https://fastapi.tiangolo.com/) for the REST API, [Pydantic](https://pydantic-docs.helpmanual.io/) for data models, and [Motor](https://motor.readthedocs.io/) or [PyMongo](https://pymongo.readthedocs.io/) to access MongoDB. Use [python-dotenv](https://github.com/theskumar/python-dotenv) or similar for environment config. For any cryptography, use [PyCA Cryptography](https://cryptography.io/) (avoid writing your own crypto).  
- **Database:** MongoDB (4.4+), preferably with the [Enterprise Encryption](https://www.mongodb.com/docs/manual/core/security-encryption-at-rest/) engine enabled, or use [MongoDB Field-Level Encryption](https://www.mongodb.com/docs/drivers/security/client-side-field-level-encryption/).  
- **Frontend (Officer/IO app):** Flutter (latest stable) for the cross-platform app. Write platform-specific code in Kotlin (for Android) via Flutter’s [MethodChannel] to access telephony APIs. For SMS: use Android’s `android.telephony.SmsManager` (available API). For receiving SMS, use a `BroadcastReceiver` with `SMS_RECEIVED` intent. Flutter plugins that merely wrap SmsManager (like [sms](https://pub.dev/packages/sms)) may be used only if they meet updated policies.  
- **Android APIs:** You may use standard Android libraries (`androidx`) and the official telephony APIs. No private or undocumented APIs. For permissions and checking SIM status, you can use [TelephonyManager](https://developer.android.com/reference/android/telephony/TelephonyManager) (to verify SIM is ready) and [SubscriptionManager](https://developer.android.com/reference/android/telephony/SubscriptionManager) if needed.  
- **Security libraries:** For hashing (e.g. SHA-256), use Python’s built-in `hashlib` or a vetted library. For OAuth/JWT (if implemented), use [PyJWT](https://pyjwt.readthedocs.io/) or [Authlib](https://docs.authlib.org/). For HTTP client in Flutter, use [dio](https://pub.dev/packages/dio) or [http](https://pub.dev/packages/http) with TLS.  
- **Testing:** Use [pytest](https://docs.pytest.org/) for Python unit tests, and Flutter’s built-in test framework for Dart. Include tests for API endpoints (e.g. with [httpx](https://www.python-httpx.org/) or [requests](https://docs.python-requests.org/) mocking) and SMS handling (mock SmsManager in Android or use integration tests on a device with an emulator SMS app).  
- **Dev Tools:** Git/GitHub for version control. Pre-commit linters/formatters (e.g. [flake8](https://flake8.pycqa.org/) for Python, [dartfmt]/`flutter format` for Dart). CI can use GitHub Actions to run lint and tests on push.  
- **Note:** Do not introduce large third-party dependencies without review. Only use libraries from official sources (PyPI, pub.dev, Maven Central). Avoid deprecated or unmaintained packages.  

## 5. Error Handling  
Develop a robust failure-management strategy:  

- **State Transitions & Timeouts:** Model each location request as a state machine. Example states: `CREATED` → `PENDING_IO` → `SENT` → `RESPONDED` → `COMPLETED` or `FAILED`. Explicitly code these transitions and disallow jumps (e.g. you cannot go from `CREATED` directly to `COMPLETED`). On each state change, log a timestamp. If expected next events do not occur within a deadline, move to an error state. For instance: if SMS is sent but no delivery report in 2 minutes, flag `SMS_FAILED`. If no reply in 5 minutes after sending, mark `TIMEOUT`.  
- **Retries and Backoff:** When sending SMS, use the Android delivery callback to detect failures. If an SMS fails to send (e.g. `SmsManager.RESULT_ERROR_RADIO_OFF`), retry up to 2 more times with delays (e.g. 1 minute apart). Don’t retry indefinitely. Example pseudo-code:  
  ```python
  for attempt in range(3):
      success = smsManager.sendTextMessage(...)
      if success: break
      sleep(60 * (attempt+1))
  if not success: state = FAILED
  ```  
- **User Notifications:** In the IO app, display progress and errors clearly. For example, “SMS sent, awaiting response”, “Network error: could not send SMS – retrying…”, or “Location query failed: no response”. Do not expose raw exception details to the user; instead log them and show a generic message (e.g. “An unexpected error occurred”).  
- **Logging and Alerts:** All errors (exceptions in code, SMS send failures, parse errors) must be caught and logged with context (include request ID, user ID, timestamp). For critical failures (e.g. phone permission denied, SIM not ready), send an alert to the IO (via the app UI) and mark the request as failed. In backend logs, use a structured JSON format or similar so logs can be audited. Example log entry:  
  ```json
  {"timestamp": "...", "request_id": "LR-2026-0042", "user": "IO-7", 
   "event": "SMS_SEND_ERROR", "details": "RESULT_ERROR_RADIO_OFF"}
  ```  
- **Timeout Handling:** If SMS reply isn’t received in a reasonable window (e.g. 5–10 minutes; configurable), automatically timestamp the request as `TIMEOUT` and notify the IO. The IO can then retry or cancel. This prevents requests from hanging indefinitely.  
- **Transaction Consistency:** Use database transactions or atomic updates for critical steps. For example, mark `SMS_SENT` only after confirming the SMS dispatch Intent was enqueued. Ensure that if the app or server crashes, no state is lost. MongoDB with transactions (on a replica set) or using two-phase updates (insert audit record, then update state) is recommended.  

## 6. AI Usage Boundaries  
- **Allowed (Tooling & Documentation Only):** You may use AI (e.g. ChatGPT) for boilerplate code examples, design brainstorming, documentation, or clarifying API usage. For example, using AI to generate a code snippet for setting up an Android BroadcastReceiver is fine. However, **always review and test** any AI-generated code for correctness and security. Treat AI output as a starting point, not authoritative.  
- **Forbidden (No Unchecked AI Decisions):** Do not use AI to make any operational decisions for the app. Specifically:  
  - *Legal/Policy Advice:* Do not rely on AI for legal interpretation (e.g. determining if an SMS message content is admissible evidence or if a location query is lawful). That should be determined by legal experts or official guidelines.  
  - *Content Parsing/Evidence Analysis:* The app may display parsed location data, but AI must not be used to *interpret* evidence (e.g. do not have AI read the SMS and conclude “this location was near a known suspect”). Humans must review all findings.  
  - *Automated SMS Templates:* SMS queries often require precise operator formats. Do not generate or modify SMS templates with AI. Only use operator-supplied templates or officially approved formats. For example, if the operator’s SMS syntax is `LOCATE <country code><number>`, do not have AI “optimize” or “shorten” it – stick to the documented command.  
- **Personal/Privacy Data:** Do not input any real phone numbers or personal data into AI tools. When testing, use synthetic data.  
- **Compliance:** Follow any relevant organizational or provider guidelines on AI use. If AI is used to generate unit tests or code comments, ensure no sensitive data or logic is leaked to the AI.

## 7. Repository Guidelines  
- **Branching & PRs:** Use Git (GitHub/GitLab). Adopt a lightweight flow (e.g. `main` for stable code, feature branches for new work). Protect `main` branch with required pull-request (PR) review. Each PR should be reviewed by at least one teammate (or mentor) before merge. Use descriptive commit messages.  
- **Secrets Management:** Never commit credentials, keys, or passwords in code. Use a `.env` file (add to `.gitignore`) or CI secrets for environment variables (e.g. `os.getenv("DB_PASSWORD")`). If using MongoDB, use an authentication mechanism (username/password or X.509 certificates) stored securely. Rotate secrets regularly.  
- **CI/CD Checks:** Set up a CI pipeline (e.g. GitHub Actions) to run linters and tests on each push/PR. For example, `flake8` for Python, `dart analyze` for Dart, and unit tests. Don’t allow merging code that fails lint or has test failures.  
- **License & Documentation:** Include an appropriate open-source license (e.g. MIT or Apache-2.0) if required by the organization. Add a `README.md` and API documentation (FastAPI’s built-in OpenAPI docs). Provide a `CHANGELOG.md` to record changes.  
- **Issue Templates & Project Tracking:** Use issue/bug/feature templates to standardize requests. Track progress with milestones or a Kanban board. Label issues as “security”, “bug”, “feature”, etc. Write clear descriptions with steps to reproduce or acceptance criteria.  
- **Deployment Constraints:** This app is intended for *internal, managed deployment only*. Do not configure any automated release to the public Play Store. Mark versions clearly (semantic versioning). If distributing via an MDM (Mobile Device Management) system, ensure the app is signed with the correct enterprise certificate. As a safety measure, hardcode an environment check so the app refuses to run on non-authorized devices (for instance, verify it’s enrolled as a work app).  
- **Code Review & Updates:** Periodically review third-party libraries for updates and vulnerabilities. Remove any library no longer needed. Document any platform-specific instructions (e.g. “Enable SMS permission in Work Profile settings”).  
- **Data Retention Policy:** While not strictly code, the repo should include (in README or a separate doc) a note on data retention: e.g. “Location requests are purged after 90 days and masked in logs, per policy.” Make sure the code implements or at least facilitates that.  

---  

### ✅ MVP Compliance Checklist  

- [ ] **Officer Request:** Officer can create a location request (enter number, select operator, add case info).  
- [ ] **Secure Link:** System generates a single-use link/token; link does not expose sensitive data.  
- [ ] **IO Access:** IO opens the link, reviews request details.  
- [ ] **SMS Send:** IO taps “Request Location” and the app sends SMS via `SmsManager`. The SMS originates from the IO’s SIM (verified by telecom).  
- [ ] **Receive & Display:** Incoming SMS reply is captured by the app, raw text stored in DB. Parsed location info is displayed to IO.  
- [ ] **Audit Logs:** All steps (request creation, SMS sent, response received) are logged with timestamps and user IDs.  
- [ ] **Data Protection:** Sensitive fields (phone number, location) are encrypted or masked in the database and UI.  
- [ ] **Permission Handling:** The app properly requests and checks **android.permission.SEND_SMS** and **RECEIVE_SMS** (hard-restricted; assume allowlist).  
- [ ] **Error Handling:** Failures (e.g. SMS not sent, no response) move the request to an error state and notify the IO.  
- [ ] **No Forbidden Actions:** The app does not scrape WhatsApp, does not store hardcoded credentials, and is set up for internal deployment (not Play Store).  
- [ ] **Audit-Ready:** After running the MVP, one can review the logs and state transitions for each request without needing to touch the SMS replies.  

*Assumptions:* Deployment is via a corporate-managed Android environment (so SMS permissions can be granted by MDM). No external SSO or auth is yet in place. All operator SMS formats/phone numbers will be provided by the telecom/legal team in configuration files. Any unspecified detail (e.g. exact retry counts) is up to developer discretion but should follow usual best practices.  

