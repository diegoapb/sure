class Assistant::Function::UpdateMerchant < Assistant::Function
  class << self
    def name
      "update_merchant"
    end

    def description
      <<~INSTRUCTIONS
        Updates an existing merchant's name, color, or website URL.

        Identify the merchant by its current name. At least one of new_name, color,
        or website_url must be provided. Use get_merchants first to confirm the
        merchant exists.
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
          description: "Current name of the merchant to update",
          enum: family_merchant_names
        },
        new_name: {
          type: "string",
          description: "New name for the merchant (optional)"
        },
        color: {
          type: "string",
          description: "New hex color code (optional)"
        },
        website_url: {
          type: "string",
          description: "New website URL, used to regenerate the logo (optional)"
        }
      }
    )
  end

  def call(params = {})
    merchant = family.merchants.find_by(name: params["name"].to_s.strip)
    return error("not_found", "Merchant '#{params["name"]}' not found.") unless merchant

    attrs = {}
    attrs[:name] = params["new_name"].strip if params["new_name"].present?
    attrs[:color] = params["color"].strip if params["color"].present?
    attrs[:website_url] = params["website_url"].strip if params["website_url"].present?

    return error("no_changes", "Provide at least one of new_name, color, or website_url to update.") if attrs.empty?

    if merchant.update(attrs)
      { success: true, merchant: serialize(merchant), message: "Merchant updated." }
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
