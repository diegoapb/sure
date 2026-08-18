require "test_helper"

class Assistant::Function::PauseRecurringTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @recurring_transaction = recurring_transactions(:netflix_subscription)
    @fn = Assistant::Function::PauseRecurringTransaction.new(@user)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "pause_recurring_transaction", definition[:name]
    assert_not_empty definition[:description]
    assert_includes definition[:params_schema][:required], "id"
  end

  test "pauses an active recurring transaction" do
    result = @fn.call("id" => @recurring_transaction.id)

    assert result[:success]
    assert_equal "inactive", result[:recurring_transaction][:status]
    assert @recurring_transaction.reload.inactive?
  end

  test "soft error when already paused" do
    result = @fn.call("id" => recurring_transactions(:inactive_subscription).id)

    assert_equal false, result[:success]
    assert_equal "already_paused", result[:error]
  end

  test "soft error when not found" do
    result = @fn.call("id" => SecureRandom.uuid)

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end

  test "cannot pause a recurring transaction from another family" do
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

    result = @fn.call("id" => other_rt.id)

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
    assert other_rt.reload.active?
  end
end
