class Assistant::Function::DeleteMerchant < Assistant::Function
  class << self
    def name
      "delete_merchant"
    end

    def description
      <<~INSTRUCTIONS
        Permanently deletes an existing merchant from the user's family.

        Identify the merchant by its current name. Transactions assigned to the
        merchant are kept but unlinked from it. This action cannot be undone, so
        confirm with the user before deleting. Use get_merchants first to confirm
        the merchant exists.
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
          description: "Name of the merchant to delete",
          enum: family_merchant_names
        }
      }
    )
  end

  def call(params = {})
    merchant = family.merchants.find_by(name: params["name"].to_s.strip)
    return error("not_found", "Merchant '#{params["name"]}' not found.") unless merchant

    merchant.destroy!

    { success: true, merchant: { id: merchant.id, name: merchant.name }, message: "Merchant '#{merchant.name}' deleted." }
  end

  private
    def error(key, message)
      { success: false, error: key, message: message }
    end
end
