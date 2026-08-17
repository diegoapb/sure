require "test_helper"

class Assistant::Function::UpdateMerchantTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @merchant = merchants(:netflix)
    @fn = Assistant::Function::UpdateMerchant.new(@user)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "update_merchant", definition[:name]
    assert_not_empty definition[:description]
    assert_includes definition[:params_schema][:required], "name"
  end

  test "params_schema enumerates family merchant names" do
    schema = @fn.params_schema
    assert_includes schema[:properties][:name][:enum], @merchant.name
  end

  test "updates merchant name" do
    result = @fn.call("name" => @merchant.name, "new_name" => "Netflix Inc")

    assert result[:success]
    assert_equal "Netflix Inc", @merchant.reload.name
  end

  test "updates merchant color" do
    result = @fn.call("name" => @merchant.name, "color" => "#6471eb")

    assert result[:success]
    assert_equal "#6471eb", @merchant.reload.color
  end

  test "updates merchant website_url" do
    result = @fn.call("name" => @merchant.name, "website_url" => "netflix.com")

    assert result[:success]
    assert_equal "netflix.com", @merchant.reload.website_url
  end

  test "soft error when merchant not found" do
    result = @fn.call("name" => "Nonexistent", "new_name" => "X")

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end

  test "soft error when no changes provided" do
    result = @fn.call("name" => @merchant.name)

    assert_equal false, result[:success]
    assert_equal "no_changes", result[:error]
  end

  test "soft error when new_name already taken in family" do
    result = @fn.call("name" => @merchant.name, "new_name" => merchants(:amazon).name)

    assert_equal false, result[:success]
    assert_equal "validation_failed", result[:error]
  end

  test "cannot update a merchant from another family" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en", country: "US", timezone: "UTC")
    other_merchant = other_family.merchants.create!(name: "Other Merchant")

    result = @fn.call("name" => other_merchant.name, "new_name" => "Hijacked")

    assert_equal false, result[:success]
    assert_equal "not_found", result[:error]
  end
end
