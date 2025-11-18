"""Refactor scheduled payments

Revision ID: a1b2c3d4e5f6
Revises: c2a8f3b9d1e4
Create Date: 2025-11-17 21:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, Sequence[str], None] = 'c2a8f3b9d1e4'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # 1. Создаем новый ENUM для типов повторений
    recurrencetype = sa.Enum('DAYS', 'WEEKS', 'MONTHS', 'YEARS', name='recurrencetype')
    recurrencetype.create(op.get_bind())

    # 2. Добавляем все новые колонки
    op.add_column('scheduled_payments', sa.Column('next_payment_date', sa.Date(), nullable=False, server_default=sa.text('CURRENT_DATE')))
    op.add_column('scheduled_payments', sa.Column('period_start_date', sa.Date(), nullable=True))
    op.add_column('scheduled_payments', sa.Column('period_end_date', sa.Date(), nullable=True))
    op.add_column('scheduled_payments', sa.Column('recurrence_type', sa.Enum('DAYS', 'WEEKS', 'MONTHS', 'YEARS', name='recurrencetype'), nullable=True))
    op.add_column('scheduled_payments', sa.Column('recurrence_interval', sa.Integer(), nullable=True))
    
    # 3. Убираем server_default после начального заполнения
    op.alter_column('scheduled_payments', 'next_payment_date', server_default=None)

    # 4. Удаляем старые колонки
    op.drop_column('scheduled_payments', 'payment_day_of_month')
    op.drop_column('scheduled_payments', 'statement_day_of_month')


def downgrade() -> None:
    # 1. Возвращаем старые колонки
    op.add_column('scheduled_payments', sa.Column('statement_day_of_month', sa.INTEGER(), autoincrement=False, nullable=False, server_default='1'))
    op.add_column('scheduled_payments', sa.Column('payment_day_of_month', sa.INTEGER(), autoincrement=False, nullable=False, server_default='1'))

    # 2. Удаляем новые
    op.drop_column('scheduled_payments', 'recurrence_interval')
    op.drop_column('scheduled_payments', 'recurrence_type')
    op.drop_column('scheduled_payments', 'period_end_date')
    op.drop_column('scheduled_payments', 'period_start_date')
    op.drop_column('scheduled_payments', 'next_payment_date')

    # 3. Удаляем ENUM
    op.execute('DROP TYPE recurrencetype;')