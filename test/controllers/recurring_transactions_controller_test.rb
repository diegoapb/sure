require "test_helper"

class RecurringTransactionsControllerTest < ActionDispatch::IntegrationTest
  include EntriesTestHelper

  setup do
    sign_in @user = users(:family_admin)
    @recurring_transaction = recurring_transactions(:netflix_subscription)
  end

  test "index renders list view" do
    get recurring_transactions_url

    assert_response :success
  end

  test "index renders calendar view for a given month" do
    get recurring_transactions_url(view: "calendar", month: Date.current.strftime("%Y-%m"))

    assert_response :success
  end

  test "creates a manual recurring transaction" do
    assert_difference "RecurringTransaction.count", 1 do
      post recurring_transactions_url, params: {
        recurring_transaction: {
          name: "Gym membership",
          nature: "outflow",
          amount: 50,
          currency: "USD",
          expected_day_of_month: 10,
          account_id: accounts(:depository).id
        }
      }
    end

    created = RecurringTransaction.order(:created_at).last
    assert_equal "Gym membership", created.name
    assert created.manual?
    assert_equal 50, created.amount
    assert_redirected_to recurring_transactions_path
  end

  test "create with income nature stores a negative amount" do
    post recurring_transactions_url, params: {
      recurring_transaction: {
        name: "Salary",
        nature: "inflow",
        amount: 1000,
        currency: "USD",
        expected_day_of_month: 1
      }
    }

    assert_equal(-1000, RecurringTransaction.order(:created_at).last.amount)
  end

  test "create without name or merchant re-renders the form" do
    assert_no_difference "RecurringTransaction.count" do
      post recurring_transactions_url, params: {
        recurring_transaction: {
          nature: "outflow",
          amount: 50,
          currency: "USD",
          expected_day_of_month: 10
        }
      }
    end

    assert_response :unprocessable_entity
  end

  test "updates a recurring transaction" do
    patch recurring_transaction_url(@recurring_transaction), params: {
      recurring_transaction: {
        name: "Netflix Premium",
        merchant_id: "",
        nature: "outflow",
        amount: 22.99,
        expected_day_of_month: 20,
        account_id: @recurring_transaction.account_id
      }
    }

    @recurring_transaction.reload
    assert_equal "Netflix Premium", @recurring_transaction.name
    assert_nil @recurring_transaction.merchant_id
    assert_equal 22.99, @recurring_transaction.amount
    assert_equal 20, @recurring_transaction.expected_day_of_month
    assert_equal 20, @recurring_transaction.next_expected_date.day
    assert_redirected_to recurring_transactions_path
  end

  test "match lists candidate transactions" do
    create_transaction(account: accounts(:depository), amount: 16.50, date: Date.current.beginning_of_month + 4.days, name: "Possible Netflix")

    get match_recurring_transaction_url(@recurring_transaction, due_date: Date.current.beginning_of_month + 4.days)

    assert_response :success
  end

  test "create_match links the transaction and records the occurrence" do
    entry = create_transaction(account: accounts(:depository), amount: 16.50, date: Date.current, name: "Netflix manual")

    assert_changes -> { @recurring_transaction.reload.occurrence_count }, from: 3, to: 4 do
      post match_recurring_transaction_url(@recurring_transaction, entry_id: entry.id)
    end

    assert_equal @recurring_transaction, entry.entryable.reload.recurring_transaction
    assert_equal entry.date, @recurring_transaction.reload.last_occurrence_date
    assert_redirected_to recurring_transactions_path
  end

  test "destroy removes the pattern but keeps linked transactions" do
    entry = create_transaction(account: accounts(:depository), amount: 16.50, date: Date.current, name: "Netflix manual")
    @recurring_transaction.link_transaction!(entry.entryable)

    assert_difference "RecurringTransaction.count", -1 do
      delete recurring_transaction_url(@recurring_transaction)
    end

    assert entry.entryable.reload.persisted?
    assert_nil entry.entryable.recurring_transaction_id
  end
end
