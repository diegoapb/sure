require "test_helper"

class Assistant::Function::CreateTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @account = accounts(:depository)
    @function = Assistant::Function::CreateTransaction.new(@user)
  end

  test "creates an expense transaction with related records" do
    category = categories(:food_and_drink)
    tag = tags(:one)

    result = nil
    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      result = @function.call(
        "account_id" => @account.id,
        "name" => "Coffee",
        "amount" => 4.50,
        "date" => Date.current.to_s,
        "nature" => "outflow",
        "notes" => "Created by assistant",
        "category_id" => category.id,
        "tag_ids" => [ tag.id ]
      )
    end

    assert_equal true, result[:success]

    transaction = Transaction.find(result[:transaction][:id])
    entry = transaction.entry
    assert_equal "Coffee", entry.name
    assert_equal 4.50, entry.amount
    assert_equal @account, entry.account
    assert_equal "Created by assistant", entry.notes
    assert_equal category, transaction.category
    assert_equal [ tag.id ], transaction.tag_ids
    assert entry.user_modified?
    assert transaction.locked?(:tag_ids)
  end

  test "creates an inflow with a negative signed amount" do
    result = @function.call(
      "account_id" => @account.id,
      "name" => "Paycheck",
      "amount" => 100,
      "date" => Date.current.to_s,
      "nature" => "inflow"
    )

    assert_equal true, result[:success]
    assert_equal "income", result[:transaction][:classification]

    entry = Transaction.find(result[:transaction][:id]).entry
    assert_equal(-100, entry.amount)
  end

  test "rejects invalid amounts and dates" do
    base_params = {
      "account_id" => @account.id,
      "name" => "Coffee",
      "amount" => 10,
      "date" => Date.current.to_s,
      "nature" => "outflow"
    }

    result = @function.call(base_params.merge("amount" => -10))
    assert_equal "invalid_amount", result[:error]

    result = @function.call(base_params.merge("amount" => "not a number"))
    assert_equal "invalid_amount", result[:error]

    result = @function.call(base_params.merge("date" => "15/08/2026"))
    assert_equal "invalid_date", result[:error]

    result = @function.call(base_params.merge("nature" => "expense"))
    assert_equal "invalid_nature", result[:error]
  end

  test "rejects categories outside the family" do
    other_category = Category.create!(
      family: families(:empty),
      name: "Other",
      color: "#e99537",
      lucide_icon: "tag"
    )

    result = @function.call(
      "account_id" => @account.id,
      "name" => "Coffee",
      "amount" => 10,
      "date" => Date.current.to_s,
      "nature" => "outflow",
      "category_id" => other_category.id
    )

    assert_equal false, result[:success]
    assert_equal "invalid_category", result[:error]
  end

  test "does not let read-only collaborators create transactions" do
    function = Assistant::Function::CreateTransaction.new(users(:family_member))

    result = function.call(
      "account_id" => accounts(:credit_card).id,
      "name" => "Should not be saved",
      "amount" => 10,
      "date" => Date.current.to_s,
      "nature" => "outflow"
    )

    assert_equal false, result[:success]
    assert_equal "not_authorized", result[:error]
  end

  test "returns account_not_found for accounts outside the user's reach" do
    result = @function.call(
      "account_id" => SecureRandom.uuid,
      "name" => "Coffee",
      "amount" => 10,
      "date" => Date.current.to_s,
      "nature" => "outflow"
    )

    assert_equal false, result[:success]
    assert_equal "account_not_found", result[:error]
  end
end
