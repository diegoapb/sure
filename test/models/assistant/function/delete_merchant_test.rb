require "test_helper"

class Assistant::Function::DeleteMerchantTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @merchant = merchants(:netflix)
    @fn = Assistant::Function::DeleteMerchant.new(@user)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "delete_merchant", definition[:name]
    assert_not_empty definition[:description]
    assert_includes definition[:params_schema][:required], "name"
  end

  test "deletes merchant" do
    result = @fn.call("name" => @merchant.name)

    assert result[:success]
    assert_nil Merchant.find_by(id: @merchant.id)
  end

  test "deleting a merchant unlinks its transactions" do
    transaction = @family.transactions.first
    transaction.update!(merchant: @merchant)

    result = @fn.call("name" => @merchant.name)

    assert result[:success]
    assert_nil transaction.reload.merchant_id
  end

  test "soft error when merchant not found" do
    result = @fn.call("name" => "Nonexistent")

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end

  test "cannot delete a merchant from another family" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en", country: "US", timezone: "UTC")
    other_merchant = other_family.merchants.create!(name: "Other Merchant")

    result = @fn.call("name" => other_merchant.name)

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
    assert other_merchant.reload.persisted?
  end
end
