require "test_helper"

class Assistant::Function::CreateReceivableTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @function = Assistant::Function::CreateReceivable.new(@user)
  end

  test "creates a receivable with an amortization schedule" do
    result = nil
    assert_difference [ "Account.count", "Receivable.count" ], 1 do
      result = @function.call(
        "name" => "Préstamo a Juan",
        "debtor_name" => "Juan Pérez",
        "amount" => 1_000_000,
        "term_months" => 10,
        "start_date" => Date.current.prev_month.to_s
      )
    end

    assert_equal true, result[:success]

    account = Account.find(result[:account][:id])
    receivable = account.accountable

    assert_equal "Receivable", account.accountable_type
    assert_equal 1_000_000, account.balance
    assert_equal "Juan Pérez", receivable.debtor_name
    assert_equal 10, receivable.term_months
    assert_equal 10, receivable.installments.count
    assert_equal 100_000, receivable.installments.first.total_amount
    assert_equal 10, result[:account][:installments][:count]
  end

  test "creates a receivable without a term as an open balance" do
    result = @function.call(
      "name" => "Factura pendiente",
      "debtor_name" => "Acme Corp",
      "amount" => 500,
      "subtype" => "services"
    )

    assert_equal true, result[:success]

    receivable = Account.find(result[:account][:id]).accountable
    assert_equal "services", receivable.subtype
    assert_equal 0, receivable.installments.count
  end

  test "applies interest to the schedule" do
    result = @function.call(
      "name" => "Préstamo con interés",
      "debtor_name" => "John",
      "amount" => 1000,
      "interest_rate" => 12,
      "term_months" => 12
    )

    assert_equal true, result[:success]
    receivable = Account.find(result[:account][:id]).accountable
    # 1000 * 0.01 * 1.01^12 / (1.01^12 - 1) = 88.85
    assert_equal 88.85, receivable.monthly_payment.amount
  end

  test "requires debtor_name" do
    result = @function.call("name" => "Sin deudor", "amount" => 100)

    assert_equal false, result[:success]
    assert_equal "debtor_name_required", result[:error]
  end

  test "rejects invalid subtype" do
    result = @function.call(
      "name" => "X", "debtor_name" => "Y", "amount" => 100, "subtype" => "invalid"
    )

    assert_equal false, result[:success]
    assert_equal "invalid_subtype", result[:error]
  end

  test "rejects non-positive amount" do
    result = @function.call("name" => "X", "debtor_name" => "Y", "amount" => 0)

    assert_equal false, result[:success]
    assert_equal "invalid_amount", result[:error]
  end

  test "rejects future start_date" do
    result = @function.call(
      "name" => "X", "debtor_name" => "Y", "amount" => 100,
      "start_date" => Date.current.next_month.to_s
    )

    assert_equal false, result[:success]
    assert_equal "invalid_start_date", result[:error]
  end
end
