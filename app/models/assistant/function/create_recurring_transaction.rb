class Assistant::Function::CreateRecurringTransaction < Assistant::Function
  class << self
    def name
      "create_recurring_transaction"
    end

    def description
      <<~INSTRUCTIONS
        Creates a recurring transaction pattern for the user's family (a subscription,
        rent, salary, etc.).

        IMPORTANT: this does NOT create real transactions. It registers an *expected
        pattern* — an amount expected on a given day of each month — used to project
        upcoming charges and track whether the real transaction arrived.

        Provide merchant_name (from get_merchants) or a free-text name — at least one
        is required. Amounts follow the app's sign convention: positive = expense
        (money out), negative = income (money in).

        If the family has matching historical transactions, an expected amount range
        is calculated automatically. You can also provide expected_amount_min and
        expected_amount_max explicitly for subscriptions with variable amounts.

        Use get_recurring_transactions first to avoid creating duplicates — a soft
        error is returned if a similar active pattern already exists.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "amount", "expected_day_of_month" ],
      properties: {
        amount: {
          type: "number",
          description: "Expected amount. Positive = expense, negative = income."
        },
        expected_day_of_month: {
          type: "integer",
          description: "Day of the month the transaction is expected (1-31)"
        },
        merchant_name: {
          type: "string",
          description: "Merchant the pattern belongs to (optional if name is given). Use get_merchants to find names.",
          enum: family_merchant_names
        },
        name: {
          type: "string",
          description: "Free-text name for the pattern (optional if merchant_name is given), e.g. 'Rent'"
        },
        currency: {
          type: "string",
          description: "ISO currency code (defaults to the family's currency)"
        },
        account_name: {
          type: "string",
          description: "Account the transaction is expected on (optional). Use get_accounts to find names.",
          enum: family_account_names
        },
        expected_amount_min: {
          type: "number",
          description: "Lower bound of the expected amount range (optional, requires expected_amount_max)"
        },
        expected_amount_max: {
          type: "number",
          description: "Upper bound of the expected amount range (optional, requires expected_amount_min)"
        }
      }
    )
  end

  def call(params = {})
    expected_day = params["expected_day_of_month"].to_i
    return error("invalid_day", "expected_day_of_month must be between 1 and 31.") unless expected_day.between?(1, 31)
    return error("amount_required", "Please provide the expected amount.") if params["amount"].blank?

    merchant = resolve_merchant(params["merchant_name"])
    return error("merchant_not_found", "Merchant '#{params["merchant_name"]}' not found.") if params["merchant_name"].present? && merchant.nil?

    name = params["name"].to_s.strip.presence
    return error("merchant_or_name_required", "Provide merchant_name or name.") if merchant.nil? && name.nil?

    account = resolve_account(params["account_name"])
    return error("account_not_found", "Account '#{params["account_name"]}' not found.") if params["account_name"].present? && account.nil?

    duplicate = find_duplicate(merchant, name, expected_day)
    if duplicate
      return error("already_exists", "A similar active recurring transaction already exists: '#{duplicate.merchant&.name || duplicate.name}' expected on day #{duplicate.expected_day_of_month}.")
    end

    variance_error = validate_variance_params(params)
    return variance_error if variance_error

    recurring_transaction = RecurringTransaction.build_manual(
      family: family,
      account: account,
      merchant: merchant,
      name: name,
      amount: params["amount"],
      currency: params["currency"],
      expected_day_of_month: expected_day,
      expected_amount_min: params["expected_amount_min"],
      expected_amount_max: params["expected_amount_max"]
    )

    if recurring_transaction.save
      {
        success: true,
        recurring_transaction: serialize(recurring_transaction),
        message: "Recurring transaction '#{merchant&.name || name}' created. Next expected on #{recurring_transaction.next_expected_date}."
      }
    else
      error("validation_failed", recurring_transaction.errors.full_messages.join("; "))
    end
  end

  private
    def resolve_merchant(merchant_name)
      return nil if merchant_name.blank?
      family.merchants.find_by(name: merchant_name.strip)
    end

    def resolve_account(account_name)
      return nil if account_name.blank?
      user.accessible_accounts.visible.find_by(name: account_name.strip)
    end

    def find_duplicate(merchant, name, expected_day)
      scope = family.recurring_transactions.active
        .where(expected_day_of_month: (expected_day - 2)..(expected_day + 2))

      if merchant.present?
        scope.find_by(merchant_id: merchant.id)
      else
        scope.find_by(name: name)
      end
    end

    # Parameter-shape checks only — variance derivation and defaults live in
    # RecurringTransaction.build_manual.
    def validate_variance_params(params)
      min = params["expected_amount_min"]
      max = params["expected_amount_max"]
      return nil if min.blank? && max.blank?

      return error("variance_incomplete", "Provide both expected_amount_min and expected_amount_max.") if min.blank? || max.blank?
      return error("variance_invalid", "expected_amount_min cannot be greater than expected_amount_max.") if min.to_d > max.to_d

      nil
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
