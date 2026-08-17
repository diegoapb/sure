require "test_helper"

class Assistant::Function::CreateMerchantTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @family = @user.family
    @fn = Assistant::Function::CreateMerchant.new(@user)
  end

  test "to_definition returns correct schema" do
    definition = @fn.to_definition
    assert_equal "create_merchant", definition[:name]
    assert_not_empty definition[:description]
    assert_includes definition[:params_schema][:required], "name"
  end

  test "creates merchant with defaults" do
    result = @fn.call("name" => "Spotify")

    assert result[:success]
    assert_equal "Spotify", result[:merchant][:name]
    assert_match(/\A#[0-9A-Fa-f]{6}\z/, result[:merchant][:color])

    merchant = @family.merchants.find_by(name: "Spotify")
    assert merchant.present?
  end

  test "creates merchant with explicit color and website_url" do
    result = @fn.call("name" => "Apple", "color" => "#6471eb", "website_url" => "apple.com")

    assert result[:success]
    assert_equal "#6471eb", result[:merchant][:color]
    assert_equal "apple.com", result[:merchant][:website_url]
  end

  test "soft error when name is blank" do
    result = @fn.call("name" => "  ")

    assert_equal false, result[:success]
    assert_equal "name_required", result[:error]
  end

  test "soft error when name already exists in family" do
    existing = merchants(:netflix)

    result = @fn.call("name" => existing.name)

    assert_equal false, result[:success]
    assert_equal "validation_failed", result[:error]
  end
end
