class Assistant::Function::CreateReceivable < Assistant::Function
  class << self
    def name
      "create_receivable"
    end

    def description
      <<~INSTRUCTIONS
        Creates a receivable account (cuenta por cobrar) — money someone owes the user,
        such as a personal loan to a friend, a sale on credit, rent, or professional services.

        Choose subtype from: #{Receivable::SUBTYPES.keys.join(", ")}.

        Pass term_months to generate a fixed-payment amortization schedule (French system,
        monthly installments). interest_rate is the nominal annual rate as a percentage
        (e.g. 12 for 12% per year); omit it for an interest-free receivable. Without
        term_months no installment plan is generated — the account just tracks the open balance.

        Installment due dates are start_date + 1 month, + 2 months, etc. start_date defaults
        to today. Use get_accounts afterwards to confirm the account.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "name", "debtor_name", "amount" ],
      properties: {
        name: {
          type: "string",
          description: "Account name (e.g. \"Préstamo a Juan\")"
        },
        debtor_name: {
          type: "string",
          description: "Name of the person or business that owes the money"
        },
        amount: {
          type: "number",
          description: "Total amount owed, as a positive number"
        },
        currency: {
          type: "string",
          description: "ISO 4217 currency code (e.g. COP). Defaults to the family currency."
        },
        subtype: {
          enum: Receivable::SUBTYPES.keys,
          description: "Kind of receivable"
        },
        interest_rate: {
          type: "number",
          description: "Optional nominal annual interest rate as a percentage (e.g. 12 for 12%/year). Omit for 0%."
        },
        term_months: {
          type: "integer",
          description: "Optional number of monthly installments. When given, a fixed-payment amortization schedule is generated."
        },
        start_date: {
          type: "string",
          description: "Optional date the credit was granted, in YYYY-MM-DD format. Installments are due monthly starting one month after it. Defaults to today."
        },
        debtor_contact: {
          type: "string",
          description: "Optional debtor contact info (phone, email)"
        },
        notes: {
          type: "string",
          description: "Optional notes about the receivable"
        }
      }
    )
  end

  def call(params = {})
    name = params["name"].to_s.strip
    return error("name_required", "Please provide a name for the account.") if name.blank?

    debtor_name = params["debtor_name"].to_s.strip
    return error("debtor_name_required", "Please provide the debtor's name.") if debtor_name.blank?

    amount = parse_positive_decimal(params["amount"], "amount")
    return amount if error_response?(amount)

    subtype = params["subtype"].to_s.strip.presence
    if subtype && !Receivable::SUBTYPES.key?(subtype)
      return error("invalid_subtype", "subtype must be one of: #{Receivable::SUBTYPES.keys.join(", ")}.")
    end

    interest_rate = parse_optional_non_negative_decimal(params["interest_rate"], "interest_rate")
    return interest_rate if error_response?(interest_rate)

    term_months = parse_optional_term_months(params["term_months"])
    return term_months if error_response?(term_months)

    start_date = parse_optional_date(params["start_date"])
    return start_date if error_response?(start_date)

    account = family.accounts.create_and_sync(
      {
        name: name,
        accountable_type: "Receivable",
        balance: amount,
        currency: params["currency"].to_s.strip.upcase.presence || family.currency,
        notes: params["notes"].to_s.strip.presence,
        owner: user,
        accountable_attributes: {
          debtor_name: debtor_name,
          debtor_contact: params["debtor_contact"].to_s.strip.presence,
          subtype: subtype,
          interest_rate: interest_rate,
          term_months: term_months,
          start_date: start_date,
          initial_balance: amount
        }
      },
      opening_balance_date: start_date
    )
    account.lock_saved_attributes!

    {
      success: true,
      account: serialize(account),
      message: "Receivable '#{account.name}' created for debtor '#{debtor_name}'."
    }
  rescue ActiveRecord::RecordInvalid => e
    error("validation_failed", e.record.errors.full_messages.join("; "))
  end

  private
    def parse_positive_decimal(value, field)
      parsed = BigDecimal(value.to_s)
      return error("invalid_#{field}", "#{field} must be a positive number.") unless parsed.positive?

      parsed
    rescue ArgumentError, TypeError
      error("invalid_#{field}", "#{field} must be a positive number.")
    end

    def parse_optional_non_negative_decimal(value, field)
      return nil if value.blank?

      parsed = BigDecimal(value.to_s)
      return error("invalid_#{field}", "#{field} must be a non-negative number.") if parsed.negative?

      parsed
    rescue ArgumentError, TypeError
      error("invalid_#{field}", "#{field} must be a non-negative number.")
    end

    def parse_optional_term_months(value)
      return nil if value.blank?

      parsed = Integer(value.to_s)
      return error("invalid_term_months", "term_months must be a positive integer.") unless parsed.positive?

      parsed
    rescue ArgumentError, TypeError
      error("invalid_term_months", "term_months must be a positive integer.")
    end

    def parse_optional_date(value)
      return nil if value.blank?

      date = Date.iso8601(value.to_s)
      return error("invalid_start_date", "start_date cannot be in the future.") if date > Date.current

      date
    rescue Date::Error
      error("invalid_start_date", "start_date must be in YYYY-MM-DD format.")
    end

    def serialize(account)
      receivable = account.accountable
      installments = receivable.installments.reload

      {
        id: account.id,
        name: account.name,
        type: account.accountable_type,
        subtype: account.subtype,
        balance: account.balance,
        currency: account.currency,
        balance_formatted: account.balance_money.format,
        debtor_name: receivable.debtor_name,
        interest_rate: receivable.interest_rate,
        term_months: receivable.term_months,
        start_date: receivable.start_date,
        monthly_payment: receivable.monthly_payment&.format,
        installments: {
          count: installments.size,
          first_due_date: installments.first&.due_date,
          last_due_date: installments.last&.due_date
        }
      }
    end

    def error_response?(value)
      value.is_a?(Hash) && value[:success] == false
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
