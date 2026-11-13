"""initial schema

Revision ID: 0001
Revises: 
Create Date: 2026-11-07 15:05:17.294057

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0001'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('login_attempts',
    sa.Column('email', sa.String(length=320), nullable=False),
    sa.Column('failures', sa.Integer(), nullable=False),
    sa.Column('locked_until', sa.DateTime(timezone=True), nullable=True),
    sa.PrimaryKeyConstraint('email')
    )
    op.create_table('sync_counter',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('value', sa.BigInteger(), nullable=False),
    sa.CheckConstraint('id = 1', name='single_row'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_table('users',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('email', sa.String(length=320), nullable=False),
    sa.Column('auth_hash', sa.String(length=200), nullable=False),
    sa.Column('kdf_salt', sa.LargeBinary(), nullable=False),
    sa.Column('kdf_ops', sa.Integer(), nullable=False),
    sa.Column('kdf_mem', sa.BigInteger(), nullable=False),
    sa.Column('wrapped_account_key', sa.LargeBinary(), nullable=False),
    sa.Column('public_key', sa.LargeBinary(), nullable=False),
    sa.Column('wrapped_private_key', sa.LargeBinary(), nullable=False),
    sa.Column('recovery_auth_hash', sa.String(length=200), nullable=False),
    sa.Column('recovery_wrapped_key', sa.LargeBinary(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('email')
    )
    op.create_table('items',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('owner_id', sa.Uuid(), nullable=False),
    sa.Column('blob', sa.LargeBinary(), nullable=True),
    sa.Column('revision', sa.BigInteger(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_items_owner_id'), 'items', ['owner_id'], unique=False)
    op.create_index(op.f('ix_items_revision'), 'items', ['revision'], unique=False)
    op.create_table('sessions',
    sa.Column('id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('token_hash', sa.LargeBinary(), nullable=False),
    sa.Column('device_name', sa.String(length=100), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('last_seen_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('token_hash')
    )
    op.create_index(op.f('ix_sessions_user_id'), 'sessions', ['user_id'], unique=False)
    op.create_table('grants',
    sa.Column('item_id', sa.Uuid(), nullable=False),
    sa.Column('user_id', sa.Uuid(), nullable=False),
    sa.Column('granted_by', sa.Uuid(), nullable=False),
    sa.Column('wrapped_key', sa.LargeBinary(), nullable=False),
    sa.Column('key_kind', sa.String(length=8), nullable=False),
    sa.Column('permission', sa.String(length=8), nullable=False),
    sa.Column('revision', sa.BigInteger(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
    sa.CheckConstraint("key_kind IN ('self', 'box')", name='key_kind'),
    sa.CheckConstraint("permission IN ('owner', 'write', 'read')", name='permission'),
    sa.ForeignKeyConstraint(['granted_by'], ['users.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['item_id'], ['items.id'], ondelete='CASCADE'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('item_id', 'user_id')
    )
    op.create_index(op.f('ix_grants_revision'), 'grants', ['revision'], unique=False)
    op.create_index(op.f('ix_grants_user_id'), 'grants', ['user_id'], unique=False)
    op.execute("INSERT INTO sync_counter (id, value) VALUES (1, 0)")


def downgrade() -> None:
    op.drop_index(op.f('ix_grants_user_id'), table_name='grants')
    op.drop_index(op.f('ix_grants_revision'), table_name='grants')
    op.drop_table('grants')
    op.drop_index(op.f('ix_sessions_user_id'), table_name='sessions')
    op.drop_table('sessions')
    op.drop_index(op.f('ix_items_revision'), table_name='items')
    op.drop_index(op.f('ix_items_owner_id'), table_name='items')
    op.drop_table('items')
    op.drop_table('users')
    op.drop_table('sync_counter')
    op.drop_table('login_attempts')
