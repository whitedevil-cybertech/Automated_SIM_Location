# Development Phases

## Development Phases Overview

The IFSO Location Request Management System will be developed in **five controlled phases**.

The phases are arranged so that the core workflow is validated early, while security, reliability, testing, and deployment are added progressively.

### Phase Overview

| Phase | Name | Primary Objective | Target Duration |
|---|---|---|---:|
| Phase 1 | Foundation & Architecture | Establish project structure, backend foundation, database, configuration, and development environment | Days 1–2 |
| Phase 2 | Officer Request Management | Implement officer-side request creation, validation, storage, and secure request sharing | Days 3–5 |
| Phase 3 | IO Execution & Android SMS Bridge | Implement IO review, explicit execution, authorized-device SMS workflow, and response capture | Days 6–9 |
| Phase 4 | Result Processing, Audit & Security | Implement response parsing, lifecycle management, audit trail, error handling, and security controls | Days 10–12 |
| Phase 5 | Testing, Deployment & Documentation | Perform controlled testing, deployment preparation, documentation, and final demonstration | Days 13–15 |

> **Important:** The timeline is an MVP development target. Actual integration with any operational telecom service depends on authorized documentation, approved test access, device configuration, and organizational approval.

---

## Phase Details

### Phase 1 — Foundation & Architecture

**Duration:** Days 1–2

**Objective:** Establish a clean and secure technical foundation before implementing the operational workflow.

#### Development Tasks

- Create the monorepo structure.
- Configure Flutter application.
- Configure FastAPI backend.
- Configure MongoDB/local development database.
- Establish environment-variable configuration.
- Define initial Pydantic schemas.
- Define MongoDB document structures.
- Define request lifecycle states.
- Establish API conventions.
- Configure Git repository and `.gitignore`.
- Create development/test configuration.
- Establish centralized Flutter theme and design tokens.
- Define logging and error-handling conventions.

#### Core Request States

```text
CREATED
PENDING_IO_REVIEW
EXECUTING
WAITING_RESPONSE
COMPLETED
SMS_FAILED
TIMEOUT
RESPONSE_INVALID
```

#### Deliverables

- Working development environment
- Initial Flutter application
- FastAPI application
- Database connection
- Initial API structure
- Initial data models
- Repository structure
- Environment configuration
- Basic UI theme
- Development documentation

---

### Phase 2 — Officer Request Management

**Duration:** Days 3–5

**Objective:** Allow an authorized officer/user to create and track a location request without requiring manual transfer of request information through external messaging.

#### Development Tasks

- Implement officer request form.
- Validate required fields.
- Capture target number and approved operator information.
- Apply only approved normalization rules.
- Store request in backend.
- Generate an opaque request identifier.
- Generate a secure, tokenized shareable request link.
- Implement request details screen.
- Implement request status display.
- Implement request-link sharing.
- Prevent sensitive information from being embedded directly in URLs.
- Add basic audit events for request creation and sharing.

#### Workflow

```text
Officer
   │
   ▼
Create Request
   │
   ▼
Validate Input
   │
   ▼
Store Request
   │
   ▼
Generate Secure Link
   │
   ▼
Share Link with IO
```

#### Deliverables

- Officer request screen
- Request validation
- Request API
- Database persistence
- Secure request-link mechanism
- Request details screen
- Initial audit events

---

### Phase 3 — IO Execution & Android SMS Bridge

**Duration:** Days 6–9

**Objective:** Implement the critical IO workflow while preserving the authorization boundary that the telecom request must originate from the authorized IO device/SIM.

#### Development Tasks

- Implement IO request-review screen.
- Display request details before execution.
- Require an explicit IO execution action.
- Implement Flutter-to-Kotlin communication using the Android platform bridge.
- Integrate the approved Android telephony mechanism.
- Load approved operator configuration.
- Generate the telecom request from approved configuration.
- Send the SMS from the authorized IO device/SIM.
- Capture the resulting send status.
- Implement incoming response handling where supported by the approved deployment model.
- Correlate an incoming response with the appropriate request.
- Preserve the raw response.
- Update request state.

#### Critical Architecture Boundary

```text
Backend
   │
   │ Request + approved configuration
   ▼
IO Android Device
   │
   │ Native Android Telephony
   ▼
Authorized IO SIM
   │
   │ SMS
   ▼
Telecom Service
```

The backend **does not impersonate the IO device, spoof the sender, or directly replace the authorized SIM**.

Operator-specific destinations, message formats, keywords, and parsing rules must come from authorized documentation/configuration. They must not be guessed or fabricated.

#### Deliverables

- IO review screen
- Explicit execution workflow
- Android/Kotlin telephony bridge
- SMS send integration
- Response capture mechanism
- Request/response correlation
- Raw response preservation
- Execution-state updates

> Android SMS capabilities and restrictions must be validated against the current Android platform and the actual approved deployment model before operational deployment.

---

### Phase 4 — Result Processing, Audit & Security

**Duration:** Days 10–12

**Objective:** Make the core workflow reliable, auditable, and resistant to common application and operational errors.

#### Development Tasks

- Implement response parsing.
- Preserve raw response independently from parsed fields.
- Validate parsed response data.
- Implement `COMPLETED` state.
- Implement `SMS_FAILED`.
- Implement `TIMEOUT`.
- Implement `RESPONSE_INVALID`.
- Add bounded retry handling where appropriate.
- Add idempotency protections.
- Prevent accidental duplicate execution.
- Implement audit timeline.
- Add authentication/authorization controls appropriate to the approved environment.
- Add rate limiting where appropriate.
- Add input validation and output encoding.
- Redact sensitive values from application logs.
- Add secret-management controls.
- Review tokenized-link security.
- Review data minimization.
- Add sensitive-data masking in the UI.
- Verify forensic integrity of stored raw responses.

#### Audit Example

```text
CREATED
   │
   ▼
PENDING_IO_REVIEW
   │
   ▼
EXECUTING
   │
   ▼
WAITING_RESPONSE
   │
   ├──► TIMEOUT
   │
   ├──► RESPONSE_INVALID
   │
   └──► COMPLETED
```

#### Deliverables

- Response parser
- Complete request state machine
- Error handling
- Audit timeline
- Security controls
- Redacted structured logging
- Idempotency controls
- Sensitive-data handling
- Security test cases

---

### Phase 5 — Testing, Deployment & Documentation

**Duration:** Days 13–15

**Objective:** Validate the complete MVP using synthetic/approved test data and prepare it for controlled internal demonstration or deployment.

#### Development Tasks

- Run backend unit tests.
- Run API integration tests.
- Test Flutter screens and validation.
- Test Android bridge behavior.
- Test SMS failure scenarios using an approved test environment.
- Test response parsing with synthetic fixtures.
- Test timeout behavior.
- Test duplicate execution protection.
- Test tokenized-link access.
- Test authorization boundaries.
- Review application logs for sensitive-data leakage.
- Run dependency/security checks.
- Validate environment configuration.
- Prepare deployment configuration.
- Document setup and operational workflow.
- Document known limitations.
- Prepare demonstration scenario.

#### Final Validation

The team should verify:

```text
Officer creates request
        ↓
Request stored
        ↓
Secure link generated
        ↓
IO reviews request
        ↓
IO explicitly executes request
        ↓
Authorized device/SIM sends SMS
        ↓
Response received
        ↓
Raw response preserved
        ↓
Response parsed
        ↓
Result displayed
        ↓
Audit trail updated
        ↓
Result shared with requesting officer
```

#### Deliverables

- Tested MVP
- Deployment configuration
- Test report
- Security checklist
- Documentation
- Known-limitations document
- Demonstration build
- Final project report

---

## Project Timeline

### 15-Day MVP Schedule

| Day | Primary Work | Expected Output |
|---:|---|---|
| 1 | Repository + architecture setup | Monorepo and development environment |
| 2 | FastAPI + MongoDB + models | Backend foundation |
| 3 | Officer UI | Request form |
| 4 | Request API + validation | Stored requests |
| 5 | Secure links + request tracking | Officer workflow |
| 6 | IO UI | Request review |
| 7 | Execute workflow | IO execution state |
| 8 | Kotlin/Android bridge | Native telephony integration |
| 9 | SMS/response handling | Device-side communication |
| 10 | Response parser | Structured result |
| 11 | State machine + error handling | Reliable workflow |
| 12 | Audit + security controls | Auditable MVP |
| 13 | Integration testing | End-to-end validation |
| 14 | Security/deployment testing | Controlled release candidate |
| 15 | Documentation + demonstration | Final MVP |

### Timeline Principle

Development should proceed in dependency order:

```text
Foundation
    ↓
Officer Workflow
    ↓
IO Workflow
    ↓
Telephony Integration
    ↓
Response Processing
    ↓
Security & Audit
    ↓
Testing
    ↓
Deployment
```

Do not begin advanced features before the core request-to-response workflow is stable.

---

## Phases Deliverables at a Glance

| Phase | Backend | Flutter | Android | Security/Audit | Documentation |
|---|---|---|---|---|---|
| **1. Foundation** | FastAPI, DB, models | App shell/theme | Initial setup | Environment/secrets baseline | Architecture/setup |
| **2. Officer Requests** | Request APIs | Officer workflow | — | Tokenized links | Request workflow |
| **3. IO Execution** | Execution APIs/config | IO workflow | SMS bridge | Authorization boundary | Telephony integration |
| **4. Result & Security** | Parser/state machine | Results/audit UI | Response capture | Audit, logging, idempotency | Security notes |
| **5. Testing & Deployment** | Integration tests | UI testing | Device testing | Security validation | Final documentation |

### MVP Completion Criteria

The MVP is considered functionally complete when the following controlled workflow works end-to-end:

- An officer can create a location request.
- The request is securely stored.
- A shareable request link can be generated.
- An IO can review the request.
- The IO must explicitly initiate execution.
- The approved Android device/SIM performs the outbound SMS operation.
- The system can capture and correlate the response in the approved test environment.
- The original response is preserved.
- A validated result can be displayed.
- The complete lifecycle is auditable.
- Failure and timeout states are handled explicitly.
- No real operational secrets or sensitive production data are stored in the repository.

### Scope Boundary

The following should remain outside the 15-day MVP unless explicitly required and approved:

- Maps/GIS visualization
- Automated WhatsApp integration
- Large-scale analytics
- Predictive location analysis
- AI-based interpretation of telecom responses
- Multi-agency federation
- Complex admin dashboards
- Production-scale infrastructure
- Automated bulk requests
- Reverse engineering of telecom interfaces
- Any mechanism intended to bypass telecom or device authorization controls

These can be considered future phases only after the core workflow has been validated and the necessary organizational approvals and technical requirements are available.
