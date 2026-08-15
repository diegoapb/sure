require "test_helper"

class Assistant::Function::DeleteTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @transaction = transactions(:one)
    @function = Assistant::Function::DeleteTransaction.new(@user)
  end

  test "deletes a transaction and its entry" do
    result = nil
    assert_difference [ "Entry.count", "Transaction.count" ], -1 do
      result = @function.call("id" => @transaction.id)
    end

    assert_equal true, result[:success]
    assert_equal @transaction.id, result[:transaction][:id]
    assert_not Transaction.exists?(@transaction.id)
  end

  test "does not delete split child transactions" do
    parent_entry = entries(:transaction)
    child_entry = accounts(:depository).entries.create!(
      name: "Split child",
      date: parent_entry.date,
      amount: 5,
      currency: "USD",
      parent_entry_id: parent_entry.id,
      entryable: Transaction.new
    )

    result = @function.call("id" => child_entry.entryable_id)

    assert_equal false, result[:success]
    assert_equal "split_child", result[:error]
    assert Entry.exists?(child_entry.id)
  end

  test "does not let read-only collaborators delete transactions" do
    transaction = transactions(:transfer_in)
    function = Assistant::Function::DeleteTransaction.new(users(:family_member))

    result = function.call("id" => transaction.id)

    assert_equal false, result[:success]
    assert_equal "not_authorized", result[:error]
    assert Transaction.exists?(transaction.id)
  end

  test "returns not_found for unknown ids" do
    result = @function.call("id" => SecureRandom.uuid)

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end
end
