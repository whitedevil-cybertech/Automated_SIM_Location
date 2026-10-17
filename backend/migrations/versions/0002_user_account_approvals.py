"""Add persisted account-enrollment and approval registry.

Revision ID: 0002_user_account_approvals
Revises: 0001_postgresql_core
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = "0002_user_account_approvals"
down_revision = "0001_postgresql_core"
branch_labels = None
depends_on = None

def upgrade():
    op.create_table(
        "user_accounts",
        sa.Column("user_id", sa.String(length=255), primary_key=True),
        sa.Column("email", sa.String(length=320), nullable=False, unique=True),
        sa.Column("status", sa.String(length=32), nullable=False),
        sa.Column("role", sa.String(length=32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("payload", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    )
    op.create_index("ix_user_accounts_email", "user_accounts", ["email"])
    op.create_index("ix_user_accounts_status", "user_accounts", ["status"])
    op.create_index("ix_user_accounts_role", "user_accounts", ["role"])
    op.create_index("ix_user_accounts_created_at", "user_accounts", ["created_at"])

def downgrade():
    op.drop_table("user_accounts")
