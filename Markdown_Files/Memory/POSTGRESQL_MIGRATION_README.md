# PostgreSQL Migration Proposal — IFSO Location Request Management System

## 1. Summary

This archive proposes replacing Motor/MongoDB persistence with PostgreSQL using SQLAlchemy 2.x, psycopg 3, and Alembic. The HTTP routes and Pydantic request/response schemas are intentionally unchanged. The current route-level collection calls are preserved through a small asynchronous persistence adapter, so route behavior and endpoint contracts do not need a broad rewrite.

The existing request documents include nested lifecycle structures (share-token details, execution metadata, raw response metadata, parsed result). These are preserved as JSONB payloads while high-value lookup/constraint fields are exposed as relational columns. Request identifiers and operator identifiers are primary keys; share-token hashes are unique; status/operator/owner/time/audit lookup columns are indexed.

**Important implementation limitation:** this is a migration proposal, not a production-certified release. PostgreSQL integration and concurrency tests could not be run because a PostgreSQL service and psycopg package were not available in the execution environment. The existing suite uses in-memory fake collections and therefore verifies API behavior but does not prove real database correctness. Review the persistence adapter before operational use, particularly concurrency behavior and JSONB serialization.

No original repository files were modified. Only changed/new files are included in this ZIP.

## 2. Complete file manifest

All paths are relative to the repository root. These are the only files included in this patch archive.

- `backend/app/core/config.py` — replace MongoDB settings with PostgreSQL URL/pool settings.
- `backend/app/core/database.py` — replace Motor connection manager and collection operations with async SQLAlchemy/PostgreSQL persistence adapter and table metadata.
- `backend/app/services/base.py` — remove Motor-specific service type annotations.
- `backend/requirements.txt` — remove Motor/PyMongo and add SQLAlchemy, psycopg 3, Alembic.
- `backend/tests/conftest.py` — use PostgreSQL test configuration while retaining existing fake persistence fixtures.
- `backend/tests/test_database.py` — test PostgreSQL offline handling.
- `backend/alembic.ini` — Alembic configuration.
- `backend/migrations/env.py` — migration environment.
- `backend/migrations/script.py.mako` — revision template.
- `backend/migrations/versions/0001_postgresql_core.py` — initial PostgreSQL schema migration.
- `backend/.env.example` — backend environment example.
- `.env.example` — repository-root environment example.
- `POSTGRESQL_MIGRATION_README.md` — this guide.

No Flutter, Android, API route, Pydantic schema, authentication, field encryption, share-link, or business-workflow files are included as changed files.

## 3. Dependencies added and removed

Added:
- `SQLAlchemy>=2.0.0`
- `psycopg[binary]>=3.1.0`
- `alembic>=1.13.0`

Removed:
- `motor`
- `pymongo`

Other existing backend dependencies are retained.

## 4. PostgreSQL configuration

Install the updated dependencies in the backend's existing virtual environment:

```bash
cd backend
python -m pip install -r requirements.txt
```

Copy `backend/.env.example` to `backend/.env` (or configure environment variables through the deployment platform). Set `DATABASE_URL` to a PostgreSQL URL, for example:

```text
DATABASE_URL=postgresql+psycopg://ifso_app:YOUR_SECRET@localhost:5432/ifso_location
```

Do not commit `.env` or real credentials. Use a dedicated least-privilege database role. The application URL is read from `DATABASE_URL`; the default local URL assumes PostgreSQL authentication is configured locally and contains no embedded password.

## 5. Create the database

Using a PostgreSQL administrator account, create a dedicated role and database. Replace the sample password interactively or use your approved secret-management mechanism:

```sql
CREATE ROLE ifso_app LOGIN;
-- Set the role password using your database administration procedure.
CREATE DATABASE ifso_location OWNER ifso_app;
```

Do not run these commands against production without DBA approval. They are examples, not automatically executed by this patch.

## 6. Apply Alembic migrations

From the repository root, with `DATABASE_URL` set:

```bash
python -m pip install -r backend/requirements.txt
alembic -c backend/alembic.ini upgrade head
```

The initial migration creates `location_requests`, `operators`, and `audit_logs`, with relational identifier/lookup columns and JSONB payloads. The migration does not import MongoDB data and does not drop any existing database.

## 7. Start the backend

From the repository root:

```bash
uvicorn backend.app.main:app --host 127.0.0.1 --port 8000
```

For development only, choose appropriate values for `APP_ENV`, `APP_DEBUG`, and the existing authentication configuration. Do not use development tokens or defaults in production.

## 8. Tests and verification

Run the existing backend tests from the repository root:

```bash
pytest backend/tests -q
```

Run a syntax compilation check:

```bash
python -m compileall backend/app backend/migrations
```

**Execution results for this archive:** 46 existing backend tests passed using the provided in-memory fake persistence fixtures. Python syntax compilation passed. PostgreSQL integration tests were not run: PostgreSQL and the psycopg package were unavailable in the build environment. The tests passing must not be interpreted as a successful live PostgreSQL integration test.

Before deployment, add/run integration tests against an isolated PostgreSQL instance for unique constraints, JSONB round-tripping, migrations, single-use share tokens under concurrent redemption, lifecycle transition races, and audit consistency.

## 9. Data transfer

No data-transfer utility is included. No production data was accessed or migrated. Before any transfer, take and verify a backup, inventory MongoDB document shapes, rehearse a one-way export/import into a separate PostgreSQL database, compare record counts and hashes, and obtain approval. Keep the MongoDB source intact until the migration has been independently reconciled and signed off. Do not point this patch at production until compatibility tests pass.

## 10. Rollback considerations

- Take a verified backup/snapshot before applying schema changes.
- This patch does not automatically migrate data and does not modify or delete the MongoDB database.
- Alembic downgrade of the initial revision drops the PostgreSQL tables and therefore deletes data stored in those tables. Do not run downgrade against a populated database unless data loss is intended and separately approved.
- A rollback to the old backend requires restoring the original MongoDB-backed code and its original dependency manifest from version control/backups. Do not merge this patch blindly.

## 11. Limitations and unverified behavior

- The ZIP contains a proposal, not an in-place update. The original repository was not modified.
- Existing route/API contracts and Pydantic document shapes are unchanged, but live PostgreSQL behavior remains unverified.
- Nested request lifecycle data is stored in JSONB alongside relational key/index columns to preserve the existing document shape. This is a compatibility-oriented transition, not a fully normalized domain model.
- The archive does not contain a MongoDB-to-PostgreSQL data-transfer utility.
- The provided test suite relies on fake collections; it does not exercise SQLAlchemy transactions or a real PostgreSQL server.
- Before production use, review transaction boundaries between request writes and audit writes, unique-token redemption concurrency, data-at-rest encryption/key compatibility, and JSONB/date-time serialization with real PostgreSQL.
