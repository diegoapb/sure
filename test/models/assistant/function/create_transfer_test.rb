require "test_helper"

class Assistant::Function::CreateTransferTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @source = accounts(:depository)
    @destination = accounts(:credit_card)
    @function = Assistant::Function::CreateTransfer.new(@user)
  end

  test "creates a transfer between two accounts" do
    result = nil
    assert_difference "Transfer.count", 1 do
      assert_difference [ "Entry.count", "Transaction.count" ], 2 do
        result = @function.call(
          "source_account_id" => @source.id,
          "destination_account_id" => @destination.id,
          "amount" => 250,
          "date" => Date.current.to_s
        )
      end
    end

    assert_equal true, result[:success]

    transfer = Transfer.find(result[:transfer][:id])
    assert_equal "confirmed", transfer.status
    assert_equal @source, transfer.outflow_transaction.entry.account
    assert_equal @destination, transfer.inflow_transaction.entry.account
    assert_equal 250, transfer.outflow_transaction.entry.amount
    assert_equal(-250, transfer.inflow_transaction.entry.amount)
    # destination is a liability, so the outflow is classified as a payment
    assert_equal "cc_payment", transfer.outflow_transaction.kind
    assert_equal "funds_movement", transfer.inflow_transaction.kind
  end

  test "applies tags to both sides of the transfer" do
    tag = tags(:one)

    result = @function.call(
      "source_account_id" => @source.id,
      "destination_account_id" => @destination.id,
      "amount" => 100,
      "date" => Date.current.to_s,
      "tag_ids" => [ tag.id ]
    )

    assert_equal true, result[:success]
    transfer = Transfer.find(result[:transfer][:id])
    assert_equal [ tag.id ], transfer.outflow_transaction.tag_ids
    assert_equal [ tag.id ], transfer.inflow_transaction.tag_ids
  end

  test "creates fee transactions when fees are given" do
    result = nil
    assert_difference "Transaction.count", 3 do
      result = @function.call(
        "source_account_id" => @source.id,
        "destination_account_id" => @destination.id,
        "amount" => 100,
        "date" => Date.current.to_s,
        "source_fee_amount" => 2.5
      )
    end

    assert_equal true, result[:success]
    assert_equal 1, result[:transfer][:fees].size
  end

  test "rejects transfers to the same account" do
    result = @function.call(
      "source_account_id" => @source.id,
      "destination_account_id" => @source.id,
      "amount" => 100,
      "date" => Date.current.to_s
    )

    assert_equal false, result[:success]
    assert_equal "same_account", result[:error]
  end

  test "rejects invalid amounts, dates, and fees" do
    base_params = {
      "source_account_id" => @source.id,
      "destination_account_id" => @destination.id,
      "amount" => 100,
      "date" => Date.current.to_s
    }

    result = @function.call(base_params.merge("amount" => -10))
    assert_equal "invalid_amount", result[:error]

    result = @function.call(base_params.merge("date" => "15/08/2026"))
    assert_equal "invalid_date", result[:error]

    result = @function.call(base_params.merge("source_fee_amount" => -1))
    assert_equal "invalid_source_fee_amount", result[:error]

    result = @function.call(base_params.merge("exchange_rate" => 0))
    assert_equal "invalid_exchange_rate", result[:error]
  end

  test "rejects tags outside the family" do
    result = @function.call(
      "source_account_id" => @source.id,
      "destination_account_id" => @destination.id,
      "amount" => 100,
      "date" => Date.current.to_s,
      "tag_ids" => [ SecureRandom.uuid ]
    )

    assert_equal false, result[:success]
    assert_equal "invalid_tags", result[:error]
  end

  test "returns not_found for accounts outside the user's reach" do
    result = @function.call(
      "source_account_id" => SecureRandom.uuid,
      "destination_account_id" => @destination.id,
      "amount" => 100,
      "date" => Date.current.to_s
    )
    assert_equal "source_account_not_found", result[:error]

    result = @function.call(
      "source_account_id" => @source.id,
      "destination_account_id" => SecureRandom.uuid,
      "amount" => 100,
      "date" => Date.current.to_s
    )
    assert_equal "destination_account_not_found", result[:error]
  end

  test "does not let read-only collaborators create transfers" do
    function = Assistant::Function::CreateTransfer.new(users(:family_member))

    result = function.call(
      "source_account_id" => @source.id,
      "destination_account_id" => @destination.id,
      "amount" => 100,
      "date" => Date.current.to_s
    )

    assert_equal false, result[:success]
    assert_equal "not_authorized", result[:error]
  end
end
