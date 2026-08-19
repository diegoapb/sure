require "test_helper"

class ReceivableTest < ActiveSupport::TestCase
  test "rejects invalid subtype" do
    receivable = Receivable.new(debtor_name: "John", subtype: "invalid")

    assert_not receivable.valid?
    assert_includes receivable.errors[:subtype], "is not included in the list"
  end

  test "requires debtor name" do
    receivable = Receivable.new

    assert_not receivable.valid?
    assert_includes receivable.errors[:debtor_name], "can't be blank"
  end

  test "calculates fixed monthly payment with interest" do
    receivable = Receivable.new(
      debtor_name: "John",
      initial_balance: 1000,
      interest_rate: 12,
      term_months: 12
    )

    # 1000 * 0.01 * 1.01^12 / (1.01^12 - 1) = 88.85
    assert_equal 88.85, receivable.monthly_payment.amount
  end

  test "calculates monthly payment without interest as straight principal split" do
    receivable = Receivable.new(
      debtor_name: "John",
      initial_balance: 1_000_000,
      term_months: 10
    )

    assert_equal 100_000, receivable.monthly_payment.amount
  end

  test "generates installment schedule on create without interest" do
    receivable = Receivable.create!(
      debtor_name: "John",
      initial_balance: 1_000_000,
      term_months: 10,
      start_date: Date.new(2026, 1, 15)
    )

    installments = receivable.installments.reload

    assert_equal 10, installments.count
    assert installments.all? { |i| i.total_amount == 100_000 }
    assert_equal 1_000_000, installments.sum(&:principal_amount)
    assert_equal Date.new(2026, 2, 15), installments.first.due_date
    assert_equal Date.new(2026, 11, 15), installments.last.due_date
    assert installments.all? { |i| i.status == "pending" }
  end

  test "installment principals sum to original principal with interest" do
    receivable = Receivable.create!(
      debtor_name: "John",
      initial_balance: 5_000_000,
      interest_rate: 18,
      term_months: 24,
      start_date: Date.new(2026, 1, 1)
    )

    installments = receivable.installments.reload

    assert_equal 24, installments.count
    assert_equal 5_000_000, installments.sum(&:principal_amount)
    assert installments.all? { |i| i.interest_amount >= 0 }
    # Interest declines as principal is repaid
    assert installments.first.interest_amount > installments.last.interest_amount
  end

  test "does not generate installments without a term" do
    receivable = Receivable.create!(debtor_name: "John", initial_balance: 500)

    assert_equal 0, receivable.installments.reload.count
  end

  test "regenerating keeps installments with payments and re-amortizes the rest" do
    receivable = Receivable.create!(
      debtor_name: "John",
      initial_balance: 1000,
      term_months: 10,
      start_date: Date.new(2026, 1, 1)
    )

    first = receivable.installments.reload.first
    first.update!(paid_amount: 100, status: "paid")

    receivable.update!(term_months: 5)
    installments = receivable.installments.reload

    assert_equal 5, installments.count
    assert_equal "paid", installments.first.status
    # Remaining principal (900) split across remaining 4 terms
    assert_equal 900, installments.drop(1).sum(&:principal_amount)
    assert_equal 225, installments.second.total_amount
  end

  test "overdue detection" do
    receivable = Receivable.create!(
      debtor_name: "John",
      initial_balance: 100,
      term_months: 1,
      start_date: 3.months.ago.to_date
    )

    installment = receivable.installments.reload.first

    assert installment.overdue?

    installment.update!(paid_amount: installment.total_amount, status: "paid")
    assert_not installment.overdue?
  end
end
