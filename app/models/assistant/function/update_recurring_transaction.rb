class Assistant::Function::UpdateRecurringTransaction < Assistant::Function
  class << self
    def name
      "update_recurring_transaction"
    end

    def description
      <<~INSTRUCTIONS
        Updates an existing recurring transaction pattern.

        Identify the pattern by its id — use get_recurring_transactions to find it.
        At least one updatable field must be provided. When expected_day_of_month
        changes, the next expected date is recalculated automatically.

        Set status to "active" to resume a paused pattern, or use
        pause_recurring_transaction to pause it.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "id" ],
      properties: {
        id: {
          type: "string",
          description: "Recurring transaction ID from get_recurring_transactions"
        },
        amount: {
          type: "number",
          description: "New expected amount. Positive = expense, negative = income."
        },
        expected_day_of_month: {
          type: "integer",
          description: "New day of the month the transaction is expected (1-31)"
        },
        merchant_name: {
          type: "string",
          description: "New merchant for the pattern. Use get_merchants to find names.",
          enum: family_merchant_names
        },
        new_name: {
          type: "string",
          description: "New free-text name for the pattern"
        },
        account_name: {
          type: "string",
          description: "New account the transaction is expected on. Use get_accounts to find names.",
          enum: family_account_names
        },
        expected_amount_min: {
          type: "number",
          description: "New lower bound of the expected amount range (requires expected_amount_max)"
        },
        expected_amount_max: {
          type: "number",
          description: "New upper bound of the expected amount range (requires expected_amount_min)"
        },
        status: {
          type: "string",
          description: "Set to 'active' to resume a paused pattern",
          enum: [ "active", "inactive" ]
        }
      }
    )
  end

  def call(params = {})
    recurring_transaction = find_recurring_transaction(params["id"])
    return error("not_found", "Recurring transaction with id '#{params["id"]}' not found.") unless recurring_transaction

    attrs = {}

    if params["expected_day_of_month"].present?
      expected_day = params["expected_day_of_month"].to_i
      return error("invalid_day", "expected_day_of_month must be between 1 and 31.") unless expected_day.between?(1, 31)
      attrs[:expected_day_of_month] = expected_day
      attrs[:next_expected_date] = RecurringTransaction.calculate_next_expected_date_from_today(expected_day)
    end

    if params["merchant_name"].present?
      merchant = family.merchants.find_by(name: params["merchant_name"].strip)
      return error("merchant_not_found", "Merchant '#{params["merchant_name"]}' not found.") unless merchant
      attrs[:merchant] = merchant
      attrs[:name] = nil
    elsif params["new_name"].present?
      attrs[:name] = params["new_name"].strip
      attrs[:merchant] = nil
    end

    if params["account_name"].present?
      account = user.accessible_accounts.visible.find_by(name: params["account_name"].strip)
      return error("account_not_found", "Account '#{params["account_name"]}' not found.") unless account
      attrs[:account] = account
    end

    variance = resolve_variance(params)
    return variance if variance.is_a?(Hash) && variance[:success] == false
    attrs.merge!(variance)

    attrs[:amount] = params["amount"] if params["amount"].present?
    attrs[:status] = params["status"] if params["status"].present?

    return error("no_changes", "Provide at least one field to update.") if attrs.empty?

    if recurring_transaction.update(attrs)
      { success: true, recurring_transaction: serialize(recurring_transaction), message: "Recurring transaction updated." }
    else
      error("validation_failed", recurring_transaction.errors.full_messages.join("; "))
    end
  end

  private
    def find_recurring_transaction(id)
      return nil unless valid_uuid?(id)
      family.recurring_transactions.accessible_by(user).find_by(id: id)
    end

    def resolve_variance(params)
      min = params["expected_amount_min"]
      max = params["expected_amount_max"]
      return {} if min.blank? && max.blank?

      return error("variance_incomplete", "Provide both expected_amount_min and expected_amount_max.") if min.blank? || max.blank?
      return error("variance_invalid", "expected_amount_min cannot be greater than expected_amount_max.") if min.to_d > max.to_d

      { expected_amount_min: min, expected_amount_max: max, expected_amount_avg: (min.to_d + max.to_d) / 2 }
    end

    def serialize(rt)
      {
        id: rt.id,
        name: rt.merchant&.name || rt.name,
        merchant: rt.merchant&.name,
        amount: rt.amount_money&.format,
        currency: rt.currency,
        expected_amount_min: rt.expected_amount_min_money&.format,
        expected_amount_max: rt.expected_amount_max_money&.format,
        expected_day_of_month: rt.expected_day_of_month,
        next_expected_date: rt.next_expected_date,
        status: rt.status,
        account: rt.account&.name
      }
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
