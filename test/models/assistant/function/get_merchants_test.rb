require "test_helper"

class Assistant::Function::GetMerchantsTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::GetMerchants.new(@user)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "get_merchants", definition[:name]
    assert_not_empty definition[:description]
  end

  test "returns family merchants alphabetically with pagination metadata" do
    result = @fn.call

    assert_equal @family.merchants.count, result[:total_results]
    assert_equal 1, result[:page]
    assert_equal @family.merchants.alphabetically.pluck(:name), result[:merchants].map { |m| m[:name] }
  end

  test "does not include merchants from another family" do
    other_family = Family.create!(name: "Other", currency: "USD", locale: "en", country: "US", timezone: "UTC")
    other_family.merchants.create!(name: "Other Merchant")

    result = @fn.call

    assert_not_includes result[:merchants].map { |m| m[:name] }, "Other Merchant"
  end
end
