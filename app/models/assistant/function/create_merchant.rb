class Assistant::Function::CreateMerchant < Assistant::Function
  class << self
    def name
      "create_merchant"
    end

    def description
      <<~INSTRUCTIONS
        Creates a new merchant for the user's family.

        Merchant names must be unique within the family. If color is omitted a palette
        color is used. Provide website_url to have a logo generated automatically.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "name" ],
      properties: {
        name: {
          type: "string",
          description: "Merchant name (must be unique within the family)"
        },
        color: {
          type: "string",
          description: "Hex color code (e.g. #e99537). Defaults to a palette color."
        },
        website_url: {
          type: "string",
          description: "Merchant website URL (e.g. netflix.com). Used to generate a logo automatically."
        }
      }
    )
  end

  def call(params = {})
    name = params["name"].to_s.strip
    return error("name_required", "Please provide a name for the merchant.") if name.blank?

    merchant = family.merchants.new(
      name: name,
      color: params["color"].presence,
      website_url: params["website_url"].presence
    )

    if merchant.save
      { success: true, merchant: serialize(merchant), message: "Merchant '#{merchant.name}' created." }
    else
      error("validation_failed", merchant.errors.full_messages.join("; "))
    end
  end

  private
    def serialize(m)
      { id: m.id, name: m.name, color: m.color, website_url: m.website_url }
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
