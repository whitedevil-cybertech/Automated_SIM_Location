"""Create PostgreSQL persistence tables.

Revision ID: 0001_postgresql_core
Revises:
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0001_postgresql_core"
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        "location_requests",
        sa.Column("request_id", sa.String(length=80), primary_key=True),
        sa.Column("case_id", sa.String(length=255), nullable=False),
        sa.Column("status", sa.String(length=64), nullable=False),
        sa.Column("operator_code", sa.String(length=32), nullable=False),
        sa.Column("submitting_officer_id", sa.String(length=255), nullable=False),
        sa.Column("share_token_hash", sa.String(length=64), nullable=True, unique=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    )
    op.create_index("ix_location_requests_status", "location_requests", ["status"])
    op.create_index("ix_location_requests_operator_code", "location_requests", ["operator_code"])
    op.create_index("ix_location_requests_submitting_officer_id", "location_requests", ["submitting_officer_id"])
    op.create_index("ix_location_requests_created_at", "location_requests", ["created_at"])
    op.create_index("ix_location_requests_status_created", "location_requests", ["status", "created_at"])
    op.create_table(
        "operators",
        sa.Column("operator_code", sa.String(length=32), primary_key=True),
        sa.Column("is_active", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    )
    op.create_table(
        "audit_logs",
        sa.Column("audit_id", sa.String(length=80), primary_key=True),
        sa.Column("request_id", sa.String(length=80), nullable=True),
        sa.Column("timestamp", sa.DateTime(timezone=True), nullable=False),
        sa.Column("actor_id", sa.String(length=255), nullable=False),
        sa.Column("event_type", sa.String(length=80), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    )
    op.create_index("ix_audit_logs_timestamp", "audit_logs", ["timestamp"])
    op.create_index("ix_audit_logs_actor_id", "audit_logs", ["actor_id"])
    op.create_index("ix_audit_logs_event_type", "audit_logs", ["event_type"])

def downgrade():
    op.drop_table("audit_logs")
    op.drop_table("operators")
    op.drop_table("location_requests")
