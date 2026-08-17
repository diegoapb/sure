require "test_helper"

class Assistant::Function::CreateRecurringTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::CreateRecurringTransaction.new(@user)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "create_recurring_transaction", definition[:name]
    assert_not_empty definition[:description]
    assert_includes definition[:params_schema][:required], "amount"
    assert_includes definition[:params_schema][:required], "expected_day_of_month"
  end

  test "params_schema enumerates family merchant and account names" do
    schema = @fn.params_schema
    assert_includes schema[:properties][:merchant_name][:enum], merchants(:netflix).name
    assert_includes schema[:properties][:account_name][:enum], accounts(:depository).name
  end

  test "creates recurring transaction with a free-text name and computed defaults" do
    result = @fn.call("name" => "Rent", "amount" => 1200, "expected_day_of_month" => 1)

    assert result[:success]

    rt = @family.recurring_transactions.find_by(name: "Rent")
    assert rt.present?
    assert rt.manual?
    assert rt.active?
    assert_equal @family.currency, rt.currency
    assert_equal 1, rt.expected_day_of_month
    assert rt.next_expected_date.future?
  end

  test "creates recurring transaction linked to a merchant and account" do
    merchant = merchants(:amazon)
    account = accounts(:depository)

    result = @fn.call(
      "merchant_name" => merchant.name,
      "amount" => 25,
      "expected_day_of_month" => 20,
      "account_name" => account.name
    )

    assert result[:success]

    rt = @family.recurring_transactions.find_by(merchant_id: merchant.id, expected_day_of_month: 20)
    assert_equal account, rt.account
    assert_nil rt.name
  end

  test "accepts explicit amount variance" do
    result = @fn.call(
      "name" => "Utilities",
      "amount" => 80,
      "expected_day_of_month" => 10,
      "expected_amount_min" => 60,
      "expected_amount_max" => 100
    )

    assert result[:success]

    rt = @family.recurring_transactions.find_by(name: "Utilities")
    assert_equal 60, rt.expected_amount_min
    assert_equal 100, rt.expected_amount_max
    assert_equal 80, rt.expected_amount_avg
  end

  test "soft error when variance is incomplete" do
    result = @fn.call("name" => "X", "amount" => 10, "expected_day_of_month" => 10, "expected_amount_min" => 5)

    assert_equal false, result[:success]
    assert_equal "variance_incomplete", result[:error]
  end

  test "soft error when variance bounds are inverted" do
    result = @fn.call(
      "name" => "X", "amount" => 10, "expected_day_of_month" => 10,
      "expected_amount_min" => 20, "expected_amount_max" => 5
    )

    assert_equal false, result[:success]
    assert_equal "variance_invalid", result[:error]
  end

  test "soft error when day is out of range" do
    result = @fn.call("name" => "X", "amount" => 10, "expected_day_of_month" => 32)

    assert_equal false, result[:success]
    assert_equal "invalid_day", result[:error]
  end

  test "soft error when neither merchant_name nor name is provided" do
    result = @fn.call("amount" => 10, "expected_day_of_month" => 10)

    assert_equal false, result[:success]
    assert_equal "merchant_or_name_required", result[:error]
  end

  test "soft error when merchant not found" do
    result = @fn.call("merchant_name" => "Nonexistent", "amount" => 10, "expected_day_of_month" => 10)

    assert_equal false, result[:success]
    assert_equal "merchant_not_found", result[:error]
  end

  test "soft error when account not found" do
    result = @fn.call("name" => "X", "amount" => 10, "expected_day_of_month" => 10, "account_name" => "Nonexistent")

    assert_equal false, result[:success]
    assert_equal "account_not_found", result[:error]
  end

  test "soft error when a similar active pattern already exists" do
    existing = recurring_transactions(:netflix_subscription)

    result = @fn.call(
      "merchant_name" => existing.merchant.name,
      "amount" => 15.99,
      "expected_day_of_month" => existing.expected_day_of_month + 1
    )

    assert_equal false, result[:success]
    assert_equal "already_exists", result[:error]
  end

  test "inactive patterns do not block creation" do
    existing = recurring_transactions(:inactive_subscription)

    result = @fn.call(
      "merchant_name" => existing.merchant.name,
      "amount" => 9.99,
      "expected_day_of_month" => existing.expected_day_of_month
    )

    assert result[:success]
  end

  test "cannot link a merchant from another family" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en", country: "US", timezone: "UTC")
    other_merchant = other_family.merchants.create!(name: "Other Merchant")

    result = @fn.call("merchant_name" => other_merchant.name, "amount" => 10, "expected_day_of_month" => 10)

    assert_equal false, result[:success]
    assert_equal "merchant_not_found", result[:error]
  end
end
