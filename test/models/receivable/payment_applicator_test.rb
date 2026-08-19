require "test_helper"

class Receivable::PaymentApplicatorTest < ActiveSupport::TestCase
  setup do
    @account = Account.create!(
      family: families(:dylan_family),
      owner: users(:family_admin),
      name: "Loan to John",
      balance: 600,
      currency: "USD",
      accountable: Receivable.create!(
        debtor_name: "John",
        initial_balance: 600,
        term_months: 3,
        start_date: Date.new(2026, 1, 1)
      )
    )
    @receivable = @account.receivable
  end

  test "partial payment marks installment partial and a follow-up completes it" do
    Receivable::PaymentApplicator.new(@receivable).apply(build_payment_transaction(150))
    first = @receivable.installments.reload.first

    assert_equal "partial", first.status
    assert_equal 150, first.paid_amount
    assert_equal 50, first.remaining_amount

    Receivable::PaymentApplicator.new(@receivable).apply(build_payment_transaction(50))
    first.reload

    assert_equal "paid", first.status
    assert_equal 200, first.paid_amount
  end

  test "payment spanning multiple installments applies oldest first" do
    Receivable::PaymentApplicator.new(@receivable).apply(build_payment_transaction(500))

    statuses = @receivable.installments.reload.map(&:status)

    assert_equal %w[paid paid partial], statuses
    assert_equal 100, @receivable.installments.last.paid_amount
  end

  test "destroying the transaction removes applications and recalculates the installment" do
    transaction = build_payment_transaction(200)
    Receivable::PaymentApplicator.new(@receivable).apply(transaction)

    assert_equal "paid", @receivable.installments.reload.first.status

    transaction.entry.destroy!

    first = @receivable.installments.reload.first
    assert_equal "pending", first.status
    assert_equal 0, first.paid_amount
  end

  private
    def build_payment_transaction(amount)
      entry = @account.entries.create!(
        name: "Payment from John",
        date: Date.current,
        amount: amount,
        currency: @account.currency,
        entryable: Transaction.new(kind: "funds_movement")
      )
      entry.transaction
    end
end
