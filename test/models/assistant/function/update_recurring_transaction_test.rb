require "test_helper"

class Assistant::Function::UpdateRecurringTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @recurring_transaction = recurring_transactions(:netflix_subscription)
    @fn = Assistant::Function::UpdateRecurringTransaction.new(@user)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "update_recurring_transaction", definition[:name]
    assert_not_empty definition[:description]
    assert_includes definition[:params_schema][:required], "id"
  end

  test "updates amount" do
    result = @fn.call("id" => @recurring_transaction.id, "amount" => 19.99)

    assert result[:success]
    assert_equal 19.99, @recurring_transaction.reload.amount.to_f
  end

  test "updates expected day and recalculates next expected date" do
    result = @fn.call("id" => @recurring_transaction.id, "expected_day_of_month" => 28)

    assert result[:success]
    @recurring_transaction.reload
    assert_equal 28, @recurring_transaction.expected_day_of_month
    assert @recurring_transaction.next_expected_date.future?
    assert_equal 28, @recurring_transaction.next_expected_date.day
  end

  test "switches pattern to a free-text name, clearing merchant" do
    result = @fn.call("id" => @recurring_transaction.id, "new_name" => "Streaming")

    assert result[:success]
    @recurring_transaction.reload
    assert_equal "Streaming", @recurring_transaction.name
    assert_nil @recurring_transaction.merchant_id
  end

  test "switches pattern to a merchant, clearing free-text name" do
    merchant = merchants(:amazon)

    result = @fn.call("id" => @recurring_transaction.id, "merchant_name" => merchant.name)

    assert result[:success]
    @recurring_transaction.reload
    assert_equal merchant.id, @recurring_transaction.merchant_id
    assert_nil @recurring_transaction.name
  end

  test "updates account" do
    account = accounts(:credit_card)

    result = @fn.call("id" => @recurring_transaction.id, "account_name" => account.name)

    assert result[:success]
    assert_equal account, @recurring_transaction.reload.account
  end

  test "updates amount variance" do
    result = @fn.call("id" => @recurring_transaction.id, "expected_amount_min" => 10, "expected_amount_max" => 20)

    assert result[:success]
    @recurring_transaction.reload
    assert_equal 10, @recurring_transaction.expected_amount_min
    assert_equal 20, @recurring_transaction.expected_amount_max
    assert_equal 15, @recurring_transaction.expected_amount_avg
  end

  test "resumes a paused pattern via status" do
    paused = recurring_transactions(:inactive_subscription)

    result = @fn.call("id" => paused.id, "status" => "active")

    assert result[:success]
    assert paused.reload.active?
  end

  test "soft error when variance is incomplete" do
    result = @fn.call("id" => @recurring_transaction.id, "expected_amount_min" => 5)

    assert_equal false, result[:success]
    assert_equal "variance_incomplete", result[:error]
  end

  test "soft error when day is out of range" do
    result = @fn.call("id" => @recurring_transaction.id, "expected_day_of_month" => 40)

    assert_equal false, result[:success]
    assert_equal "invalid_day", result[:error]
  end

  test "soft error when no changes provided" do
    result = @fn.call("id" => @recurring_transaction.id)

    assert_equal false, result[:success]
    assert_equal "no_changes", result[:error]
  end

  test "soft error when id is not a valid uuid" do
    result = @fn.call("id" => "not-a-uuid", "amount" => 10)

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end

  test "cannot update a recurring transaction from another family" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en", country: "US", timezone: "UTC")
    other_rt = other_family.recurring_transactions.create!(
      name: "Other Sub",
      amount: 10,
      currency: "USD",
      expected_day_of_month: 10,
      last_occurrence_date: Date.current,
      next_expected_date: 1.week.from_now.to_date,
      status: "active",
      manual: true
    )

    result = @fn.call("id" => other_rt.id, "amount" => 999)

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end
end
