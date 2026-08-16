class Assistant::Function::CreateAccount < Assistant::Function
  class << self
    def name
      "create_account"
    end

    def description
      <<~INSTRUCTIONS
        Creates a new manual account for the user (e.g. a checking account, credit card, loan, or property).

        Choose the account type from: #{Accountable::TYPES.join(", ")}.
        Depository, Investment, Crypto, Property, Vehicle and OtherAsset are assets;
        CreditCard, Loan and OtherLiability are liabilities.

        Balance is always a positive number — for liabilities it represents the amount owed.
        Use get_accounts afterwards to confirm the account and see its balance.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "name", "accountable_type", "balance" ],
      properties: {
        name: {
          type: "string",
          description: "Account name (e.g. \"Chase Checking\")"
        },
        accountable_type: {
          enum: Accountable::TYPES,
          description: "The type of account to create"
        },
        balance: {
          type: "number",
          description: "Current balance as a positive number. For liabilities, the amount owed."
        },
        currency: {
          type: "string",
          description: "ISO 4217 currency code (e.g. USD). Defaults to the family currency."
        },
        subtype: {
          type: "string",
          description: "Optional subtype for the account type (e.g. \"checking\" or \"savings\" for Depository, \"mortgage\" for Loan). Must be a valid subtype of the chosen accountable_type."
        },
        institution_name: {
          type: "string",
          description: "Optional financial institution name (e.g. \"Chase\")"
        },
        notes: {
          type: "string",
          description: "Optional notes about the account"
        },
        opening_balance_date: {
          type: "string",
          description: "Optional opening balance date in YYYY-MM-DD format. Defaults to 2 years ago."
        }
      }
    )
  end

  def call(params = {})
    name = params["name"].to_s.strip
    return error("name_required", "Please provide a name for the account.") if name.blank?

    accountable_type = params["accountable_type"].to_s
    accountable_class = Accountable.from_type(accountable_type)
    return error("invalid_accountable_type", "accountable_type must be one of: #{Accountable::TYPES.join(", ")}.") unless accountable_class

    balance = parse_balance(params["balance"])
    return balance if error_response?(balance)

    subtype = params["subtype"].to_s.strip.presence
    if subtype && !accountable_class::SUBTYPES.key?(subtype)
      valid_subtypes = accountable_class::SUBTYPES.keys
      return error(
        "invalid_subtype",
        valid_subtypes.any? ? "subtype must be one of: #{valid_subtypes.join(", ")}." : "#{accountable_type} accounts do not support subtypes."
      )
    end

    opening_balance_date = parse_opening_balance_date(params["opening_balance_date"])
    return opening_balance_date if error_response?(opening_balance_date)

    account = family.accounts.create_and_sync(
      {
        name: name,
        accountable_type: accountable_type,
        balance: balance,
        currency: params["currency"].to_s.strip.upcase.presence || family.currency,
        subtype: subtype,
        institution_name: params["institution_name"].to_s.strip.presence,
        notes: params["notes"].to_s.strip.presence,
        owner: user
      },
      opening_balance_date: opening_balance_date
    )
    account.lock_saved_attributes!

    {
      success: true,
      account: serialize(account),
      message: "Account '#{account.name}' created."
    }
  rescue ActiveRecord::RecordInvalid => e
    error("validation_failed", e.record.errors.full_messages.join("; "))
  end

  private
    def parse_balance(value)
      balance = BigDecimal(value.to_s)
      return error("invalid_balance", "balance must be a non-negative number.") if balance.negative?

      balance
    rescue ArgumentError, TypeError
      error("invalid_balance", "balance must be a non-negative number.")
    end

    def parse_opening_balance_date(value)
      return nil if value.blank?

      date = Date.iso8601(value.to_s)
      return error("invalid_opening_balance_date", "opening_balance_date cannot be in the future.") if date > Date.current

      date
    rescue Date::Error
      error("invalid_opening_balance_date", "opening_balance_date must be in YYYY-MM-DD format.")
    end

    def serialize(account)
      {
        id: account.id,
        name: account.name,
        type: account.accountable_type,
        subtype: account.subtype,
        # classification is a stored generated column, so read it from the
        # accountable to avoid depending on a reload after insert
        classification: account.accountable&.classification,
        balance: account.balance,
        currency: account.currency,
        balance_formatted: account.balance_money.format,
        institution_name: account.institution_name,
        status: account.status
      }
    end

    def error_response?(value)
      value.is_a?(Hash) && value[:success] == false
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
