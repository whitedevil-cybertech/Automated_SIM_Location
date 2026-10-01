# Changelog

All notable changes to the **IFSO Location Request Management System** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0] — 2026-10-01

### Phase 1 — Foundation & Architecture (Completed)

#### Added
- **Monorepo Architecture**: Clean separation into `backend/`, `mobile_app/`, `docs/`, `tests/`, and `Markdown/Memory/`.
- **FastAPI Backend Foundation**:
  - Modular project structure: `core/`, `models/`, `schemas/`, `services/`, `routes/`.
  - Pydantic Settings integration with `.env.example` and validation.
  - Root metadata endpoint `/` and health diagnostic endpoint `/api/v1/health`.
  - OpenAPI 3.0 documentation auto-generated at `/docs` and `/redoc`.
  - Centralized exception handling with structured JSON envelopes (`{"success": false, "error": {...}}`).
  - Structured redacting logger redacting phone numbers, passwords, secrets, coordinates, and raw SMS data.
- **Database & Data Abstraction**:
  - Asynchronous Motor MongoDB client (`DatabaseManager`) with connection pooling.
  - Safe degraded offline handling when MongoDB is not running locally.
  - Logical collection abstractions for `location_requests`, `operators`, and `audit_logs`.
- **Domain Models & Schemas**:
  - Request lifecycle state enum with strict state-machine transition validation:
    `CREATED`, `PENDING_IO_REVIEW`, `EXECUTING`, `WAITING_RESPONSE`, `COMPLETED`, `SMS_FAILED`, `TIMEOUT`, `RESPONSE_INVALID`.
  - Document models for `location_requests`, `operators`, and `audit_logs`.
  - Automatic phone number masking (`+91 XXXXXX1234`) and SHA-256 non-reversible hash generation.
  - Pydantic v2 validation schemas for request creation, execution, and carrier result ingestion.
- **REST API Conventions**:
  - V1 API router prefix (`/api/v1`).
  - Route conventions and OpenAPI definitions for `POST /requests`, `GET /requests/{id}`, `POST /requests/{id}/execute`, `POST /requests/{id}/result` (stubbed to 501 Not Implemented pending Phase 2).
  - Operator profiles query endpoint (`GET /api/v1/operators`) with synthetic dev data.
- **Flutter Mobile Application Foundation**:
  - Material 3 enabled Flutter architecture with light-first neutral theme.
  - Centralized design tokens: `AppColors`, `AppSpacing` (8-point system), `AppRadius`, `AppTypography` (Inter + Monospace).
  - Request lifecycle state enum in Dart with WCAG 2.2 AA accessible labels and semantic colors.
  - Home dashboard shell displaying system status, planned workflows, and forensic disclaimers.
  - Android Manifest with MDM-scoped telephony and internet permission declarations.
- **Development & Testing Infrastructure**:
  - Pytest test suite covering startup, health checks, lifecycle states, transitions, phone normalization, phone masking, logging redaction, and database offline resilience (17/17 tests passing).
  - Flutter test suite covering widget shell launch, design token verification, and request state definitions.
  - Root `.gitignore` excluding `.env`, virtualenvs, build artifacts, and sensitive files.

---

### Scope Notice
- **Phase 1 Status:** Complete.
- **Phase 2 Status:** Not yet implemented (Next target: Officer Request Management).
