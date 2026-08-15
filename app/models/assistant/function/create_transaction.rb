class Assistant::Function::CreateTransaction < Assistant::Function
  NATURES = %w[inflow outflow].freeze

  class << self
    def name
      "create_transaction"
    end

    def description
      <<~INSTRUCTIONS
        Creates a new manual transaction on one of the user's accounts.

        Use get_accounts first to find the account id, and get_categories or
        get_tags before referencing related ids.

        Amount is always a positive number — use nature to set the direction:
        "inflow" for income/money received, "outflow" for expenses/money spent.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "account_id", "name", "amount", "date", "nature" ],
      properties: {
        account_id: {
          type: "string",
          description: "Account ID from get_accounts"
        },
        name: {
          type: "string",
          description: "Transaction name (e.g. merchant or payee)"
        },
        amount: {
          type: "number",
          description: "Positive transaction amount. Direction is set by nature."
        },
        date: {
          type: "string",
          description: "Transaction date in YYYY-MM-DD format"
        },
        nature: {
          enum: NATURES,
          description: "\"inflow\" for income/money received, \"outflow\" for expenses/money spent"
        },
        currency: {
          type: "string",
          description: "ISO 4217 currency code (e.g. USD). Defaults to the account currency."
        },
        notes: {
          type: "string",
          description: "Optional transaction notes"
        },
        category_id: {
          type: "string",
          description: "Category ID from get_categories. Omit to leave uncategorized."
        },
        merchant_id: {
          type: "string",
          description: "Merchant ID currently available to the family. Omit to leave unset."
        },
        tag_ids: {
          type: "array",
          items: { type: "string" },
          description: "Tag IDs from get_tags. Omit to leave untagged."
        }
      }
    )
  end

  def call(params = {})
    account = find_account(params["account_id"])
    return error("account_not_found", "Account with id '#{params["account_id"]}' not found.") unless account
    return error("not_authorized", "You do not have permission to create transactions on this account.") unless permitted_to_create?(account)

    name = params["name"].to_s.strip
    return error("name_required", "Please provide a name for the transaction.") if name.blank?

    return error("invalid_nature", "nature must be one of: #{NATURES.join(", ")}.") unless NATURES.include?(params["nature"])

    amount = parse_amount(params["amount"])
    return amount if error_response?(amount)

    date = parse_date(params["date"])
    return date if error_response?(date)

    transaction_attrs = transaction_attributes(params)
    return transaction_attrs if error_response?(transaction_attrs)

    entry = account.entries.new(
      name: name,
      date: date,
      amount: params["nature"] == "inflow" ? -amount : amount,
      currency: params["currency"].to_s.strip.upcase.presence || account.currency,
      notes: params["notes"].presence,
      entryable: Transaction.new(transaction_attrs)
    )

    Entry.transaction do
      entry.save!
      entry.sync_account_later
      entry.lock_saved_attributes!
      entry.mark_user_modified!
      entry.transaction.lock_attr!(:tag_ids) if entry.transaction.tags.any?
    end

    {
      success: true,
      transaction: serialize(entry.transaction),
      message: "Transaction '#{entry.name}' created."
    }
  rescue ActiveRecord::RecordInvalid => e
    error("validation_failed", e.record.errors.full_messages.join("; "))
  end

  private
    def find_account(id)
      return nil unless valid_uuid?(id)

      user.accessible_accounts.visible.find_by(id: id)
    end

    def permitted_to_create?(account)
      account.permission_for(user).in?([ :owner, :full_control ])
    end

    def parse_amount(value)
      amount = BigDecimal(value.to_s)
      return error("invalid_amount", "amount must be a positive number.") unless amount.positive?

      amount
    rescue ArgumentError, TypeError
      error("invalid_amount", "amount must be a positive number.")
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      error("invalid_date", "date must be in YYYY-MM-DD format.")
    end

    def transaction_attributes(params)
      attrs = {}

      if params["category_id"].present?
        return error("invalid_category", "category_id does not belong to the user's family.") unless valid_uuid?(params["category_id"]) && family.categories.exists?(id: params["category_id"])

        attrs[:category_id] = params["category_id"]
      end

      if params["merchant_id"].present?
        return error("invalid_merchant", "merchant_id is not available to the user's family.") unless valid_uuid?(params["merchant_id"]) && family.available_merchants_for(user).exists?(id: params["merchant_id"])

        attrs[:merchant_id] = params["merchant_id"]
      end

      if params.key?("tag_ids")
        tag_ids = Array(params["tag_ids"]).map(&:to_s).reject(&:blank?)
        return error("invalid_tags", "One or more tag_ids do not belong to the user's family.") unless family.tags.where(id: tag_ids).count == tag_ids.uniq.size

        attrs[:tag_ids] = tag_ids
      end

      attrs
    end

    def serialize(transaction)
      entry = transaction.entry
      {
        id: transaction.id,
        name: entry.name,
        date: entry.date,
        amount: entry.amount.abs,
        currency: entry.currency,
        classification: entry.amount < 0 ? "income" : "expense",
        account: entry.account.name,
        notes: entry.notes,
        category: transaction.category && {
          id: transaction.category.id,
          name: transaction.category.name
        },
        merchant: transaction.merchant && {
          id: transaction.merchant.id,
          name: transaction.merchant.name
        },
        tags: transaction.tags.map { |tag| { id: tag.id, name: tag.name } }
      }
    end

    def error_response?(value)
      value.is_a?(Hash) && value[:success] == false
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
