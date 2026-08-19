# Applies a received payment (an existing Transaction on the receivable
# account) across unpaid installments, oldest due date first. Supports
# partial payments and payments spanning multiple installments; any excess
# beyond the open installments is left unapplied.
class Receivable::PaymentApplicator
  attr_reader :receivable

  def initialize(receivable)
    @receivable = receivable
  end

  def apply(transaction, amount: nil)
    remaining = (amount || transaction.entry&.amount || 0).to_d.abs
    return unless remaining.positive?

    ActiveRecord::Base.transaction do
      receivable.installments.unpaid.order(:due_date, :number).each do |installment|
        break unless remaining.positive?

        applicable = [ remaining, installment.remaining_amount ].min
        next unless applicable.positive?

        ReceivablePayment.create!(
          installment: installment,
          payment_transaction: transaction,
          amount_applied: applicable
        )
        installment.recalculate!
        remaining -= applicable
      end
    end
  end
end
