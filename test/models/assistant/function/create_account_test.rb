require "test_helper"

class Assistant::Function::CreateAccountTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @user = users(:family_admin)
    @function = Assistant::Function::CreateAccount.new(@user)
  end

  test "creates a depository account with subtype and opening balance date" do
    result = nil
    assert_difference [ "Account.count", "Depository.count" ], 1 do
      result = @function.call(
        "name" => "Assistant Checking",
        "accountable_type" => "Depository",
        "balance" => 1500.25,
        "subtype" => "checking",
        "institution_name" => "Chase",
        "opening_balance_date" => 1.year.ago.to_date.to_s
      )
    end

    assert_equal true, result[:success]

    account = Account.find(result[:account][:id])
    assert_equal "Assistant Checking", account.name
    assert_equal 1500.25, account.balance
    assert_equal "Depository", account.accountable_type
    assert_equal "checking", account.subtype
    assert_equal "Chase", account.institution_name
    assert_equal @user, account.owner
    assert_equal @user.family, account.family
    assert_equal @user.family.currency, account.currency
    assert_equal "asset", result[:account][:classification]
  end

  test "creates a liability account" do
    result = @function.call(
      "name" => "Visa Card",
      "accountable_type" => "CreditCard",
      "balance" => 300
    )

    assert_equal true, result[:success]
    assert_equal "liability", result[:account][:classification]
  end

  test "rejects invalid accountable type" do
    result = @function.call(
      "name" => "Bad",
      "accountable_type" => "Bank",
      "balance" => 100
    )

    assert_equal false, result[:success]
    assert_equal "invalid_accountable_type", result[:error]
  end

  test "rejects unknown subtype for the chosen type" do
    result = @function.call(
      "name" => "Bad Subtype",
      "accountable_type" => "Depository",
      "balance" => 100,
      "subtype" => "mortgage"
    )

    assert_equal false, result[:success]
    assert_equal "invalid_subtype", result[:error]
  end

  test "rejects invalid balance, blank name, and future opening date" do
    result = @function.call("name" => "X", "accountable_type" => "Depository", "balance" => "abc")
    assert_equal "invalid_balance", result[:error]

    result = @function.call("name" => "  ", "accountable_type" => "Depository", "balance" => 100)
    assert_equal "name_required", result[:error]

    result = @function.call(
      "name" => "X",
      "accountable_type" => "Depository",
      "balance" => 100,
      "opening_balance_date" => 1.day.from_now.to_date.to_s
    )
    assert_equal "invalid_opening_balance_date", result[:error]
  end
end
