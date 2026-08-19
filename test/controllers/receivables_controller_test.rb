require "test_helper"

class ReceivablesControllerTest < ActionDispatch::IntegrationTest
  include AccountableResourceInterfaceTest

  setup do
    sign_in @user = users(:family_admin)

    @account = Account.create!(
      family: families(:dylan_family),
      owner: @user,
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
  end

  test "creates with receivable details and generates installments" do
    assert_difference -> { Account.count } => 1,
      -> { Receivable.count } => 1,
      -> { Valuation.count } => 1 do
      post receivables_path, params: {
        account: {
          name: "Loan to Maria",
          balance: 1000,
          currency: "USD",
          accountable_type: "Receivable",
          accountable_attributes: {
            subtype: "personal_loan",
            debtor_name: "Maria",
            interest_rate: 0,
            term_months: 10,
            start_date: "2026-01-15",
            initial_balance: 1000
          }
        }
      }
    end

    created_account = Account.order(:created_at).last

    assert_equal "Loan to Maria", created_account.name
    assert_equal "Maria", created_account.receivable.debtor_name
    assert_equal 10, created_account.receivable.installments.count
    assert_equal 100, created_account.receivable.installments.first.total_amount
    assert_redirected_to created_account
    assert_enqueued_with(job: SyncJob)
  end

  test "shows payment form" do
    get new_payment_receivable_path(@account)
    assert_response :success
  end

  test "registers a payment and applies it to the oldest installment" do
    assert_difference -> { Entry.count } => 1, -> { ReceivablePayment.count } => 1 do
      post create_payment_receivable_path(@account), params: {
        payment: { amount: 200, date: Date.current.to_s }
      }
    end

    assert_redirected_to account_path(@account)

    installment = @account.receivable.installments.reload.first
    assert_equal "paid", installment.status
    assert_equal 200, installment.paid_amount

    entry = @account.entries.order(:created_at).last
    assert_equal 200, entry.amount
    assert entry.transaction.funds_movement?
  end

  test "registers a payment as transfer when destination account is given" do
    destination = accounts(:depository)

    assert_difference -> { Transfer.count } => 1, -> { ReceivablePayment.count } => 1 do
      post create_payment_receivable_path(@account), params: {
        payment: { amount: 200, date: Date.current.to_s, destination_account_id: destination.id }
      }
    end

    transfer = Transfer.order(:created_at).last
    assert_equal @account.id, transfer.outflow_transaction.entry.account_id
    assert_equal destination.id, transfer.inflow_transaction.entry.account_id
    assert_equal 200, transfer.outflow_transaction.entry.amount
  end

  test "rejects non-positive payment amounts" do
    assert_no_difference [ "Entry.count", "ReceivablePayment.count" ] do
      post create_payment_receivable_path(@account), params: {
        payment: { amount: 0, date: Date.current.to_s }
      }
    end

    assert_redirected_to account_path(@account)
  end
end
