"""Add min payment to scheduled

Revision ID: c2a8f3b9d1e4
Revises: 6f4b0f226ba2
Create Date: 2025-11-17 20:10:55.138881

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c2a8f3b9d1e4'
down_revision: Union[str, Sequence[str], None] = '6f4b0f226ba2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Добавляем новое значение 'MINIMUM_PAYMENT' в существующий тип ENUM в PostgreSQL.
    op.execute("ALTER TYPE scheduledpaymentamounttype ADD VALUE 'MINIMUM_PAYMENT'")
    
    # 2. Добавляем новую колонку для хранения процента.
    op.add_column('scheduled_payments', sa.Column('minimum_payment_percentage', sa.Numeric(precision=5, scale=2), nullable=True))


def downgrade() -> None:
    # При откате миграции удаляем колонку.
    op.drop_column('scheduled_payments', 'minimum_payment_percentage')
    
    # Откат ENUM - сложная и потенциально разрушительная операция,
    # поэтому мы ее здесь опускаем. Для удаления значения 'MINIMUM_PAYMENT'
    # потребовалось бы создать новый тип данных и перенести все данные.