class ReceivablePayment < ApplicationRecord
  belongs_to :installment, class_name: "ReceivableInstallment", foreign_key: :receivable_installment_id
  belongs_to :payment_transaction, class_name: "Transaction", foreign_key: :transaction_id

  validates :amount_applied, presence: true, numericality: { greater_than: 0 }

  # Keep the cached installment totals accurate when a payment application is
  # removed (e.g. the underlying transaction is deleted).
  after_destroy :recalculate_installment

  private
    def recalculate_installment
      installment.recalculate! if installment.persisted?
    end
end
