class ReceivableInstallment < ApplicationRecord
  STATUSES = %w[pending partial paid].freeze

  belongs_to :receivable
  has_many :payments, class_name: "ReceivablePayment", dependent: :destroy

  validates :number, presence: true, uniqueness: { scope: :receivable_id }
  validates :due_date, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :unpaid, -> { where.not(status: "paid") }

  def paid?
    status == "paid"
  end

  def overdue?
    !paid? && due_date < Date.current
  end

  def remaining_amount
    [ total_amount - paid_amount, 0 ].max
  end

  def recalculate!
    self.paid_amount = payments.sum(:amount_applied)
    self.status = if paid_amount >= total_amount
      "paid"
    elsif paid_amount.positive?
      "partial"
    else
      "pending"
    end
    self.paid_at = status == "pending" ? nil : payments.map { |p| p.payment_transaction&.entry&.date }.compact.max
    save!
  end

  def currency
    receivable.currency
  end
end
