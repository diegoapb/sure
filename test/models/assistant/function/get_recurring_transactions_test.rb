require "test_helper"

class Assistant::Function::GetRecurringTransactionsTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::GetRecurringTransactions.new(@user)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "get_recurring_transactions", definition[:name]
    assert_not_empty definition[:description]
  end

  test "returns family recurring transactions with pagination metadata" do
    result = @fn.call

    assert_equal @family.recurring_transactions.accessible_by(@user).count, result[:total_results]
    assert_equal 1, result[:page]

    names = result[:recurring_transactions].map { |rt| rt[:name] }
    assert_includes names, recurring_transactions(:netflix_subscription).merchant.name
  end

  test "filters by status" do
    result = @fn.call("status" => "inactive")

    assert result[:recurring_transactions].all? { |rt| rt[:status] == "inactive" }
    assert_includes result[:recurring_transactions].map { |rt| rt[:name] },
      recurring_transactions(:inactive_subscription).merchant.name
  end

  test "does not include recurring transactions from another family" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en", country: "US", timezone: "UTC")
    other_family.recurring_transactions.create!(
      name: "Other Sub",
      amount: 10,
      currency: "USD",
      expected_day_of_month: 10,
      last_occurrence_date: Date.current,
      next_expected_date: 1.week.from_now.to_date,
      status: "active",
      manual: true
    )

    result = @fn.call

    assert_not_includes result[:recurring_transactions].map { |rt| rt[:name] }, "Other Sub"
  end
end
