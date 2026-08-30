class Assistant::Function::CreateTransfer < Assistant::Function
  class << self
    def name
      "create_transfer"
    end

    def description
      <<~INSTRUCTIONS
        Moves money between two of the user's accounts (e.g. checking to savings,
        paying off a credit card or loan, contributing to an investment account).

        Use get_accounts first to find the source and destination account ids.

        This creates a linked pair of transactions (outflow + inflow) that is
        excluded from income/expense reports. Do NOT use create_transaction to
        record transfers between accounts.

        Amount is always positive, expressed in the source account's currency.
        If the accounts use different currencies, an exchange rate is looked up
        automatically for the given date; pass exchange_rate to override it.
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [ "source_account_id", "destination_account_id", "amount", "date" ],
      properties: {
        source_account_id: {
          type: "string",
          description: "Account ID (from get_accounts) the money leaves from"
        },
        destination_account_id: {
          type: "string",
          description: "Account ID (from get_accounts) the money goes to"
        },
        amount: {
          type: "number",
          description: "Positive amount to transfer, in the source account's currency"
        },
        date: {
          type: "string",
          description: "Transfer date in YYYY-MM-DD format"
        },
        exchange_rate: {
          type: "number",
          description: "Optional custom exchange rate when the accounts use different currencies. Omit to use the rate on record for the date."
        },
        source_fee_amount: {
          type: "number",
          description: "Optional fee charged on the source account, in its currency"
        },
        destination_fee_amount: {
          type: "number",
          description: "Optional fee charged on the destination account, in its currency"
        },
        tag_ids: {
          type: "array",
          items: { type: "string" },
          description: "Tag IDs from get_tags to apply to both sides of the transfer. Omit to leave untagged."
        }
      }
    )
  end

  def call(params = {})
    source_account = find_account(params["source_account_id"])
    return error("source_account_not_found", "Account with id '#{params["source_account_id"]}' not found.") unless source_account

    destination_account = find_account(params["destination_account_id"])
    return error("destination_account_not_found", "Account with id '#{params["destination_account_id"]}' not found.") unless destination_account

    return error("same_account", "source_account_id and destination_account_id must be different accounts.") if source_account.id == destination_account.id

    unless permitted_to_transact?(source_account) && permitted_to_transact?(destination_account)
      return error("not_authorized", "You do not have permission to create transactions on both accounts.")
    end

    amount = parse_positive_decimal(params["amount"], "amount")
    return amount if error_response?(amount)

    date = parse_date(params["date"])
    return date if error_response?(date)

    exchange_rate = parse_optional_positive_decimal(params["exchange_rate"], "exchange_rate")
    return exchange_rate if error_response?(exchange_rate)

    source_fee_amount = parse_optional_fee(params["source_fee_amount"], "source_fee_amount")
    return source_fee_amount if error_response?(source_fee_amount)

    destination_fee_amount = parse_optional_fee(params["destination_fee_amount"], "destination_fee_amount")
    return destination_fee_amount if error_response?(destination_fee_amount)

    tag_ids = validate_tag_ids(params)
    return tag_ids if error_response?(tag_ids)

    transfer = Transfer::Creator.new(
      family: family,
      source_account_id: source_account.id,
      destination_account_id: destination_account.id,
      date: date,
      amount: amount,
      exchange_rate: exchange_rate,
      source_fee_amount: source_fee_amount,
      destination_fee_amount: destination_fee_amount,
      tag_ids: tag_ids
    ).create

    {
      success: true,
      transfer: serialize(transfer),
      message: "Transfer of #{Money.new(amount, source_account.currency).format} from '#{source_account.name}' to '#{destination_account.name}' created."
    }
  rescue Money::ConversionError
    error("missing_exchange_rate", "No exchange rate found from #{source_account.currency} to #{destination_account.currency} on #{date}. Pass exchange_rate to set one manually.")
  rescue ActiveRecord::RecordInvalid => e
    error("validation_failed", e.record.errors.full_messages.join("; "))
  end

  private
    def find_account(id)
      return nil unless valid_uuid?(id)

      user.accessible_accounts.visible.find_by(id: id)
    end

    def permitted_to_transact?(account)
      account.permission_for(user).in?([ :owner, :full_control ])
    end

    def parse_positive_decimal(value, field)
      parsed = BigDecimal(value.to_s)
      return error("invalid_#{field}", "#{field} must be a positive number.") unless parsed.positive?

      parsed
    rescue ArgumentError, TypeError
      error("invalid_#{field}", "#{field} must be a positive number.")
    end

    def parse_optional_positive_decimal(value, field)
      return nil if value.blank?

      parse_positive_decimal(value, field)
    end

    def parse_optional_fee(value, field)
      return nil if value.blank?

      parsed = BigDecimal(value.to_s)
      return error("invalid_#{field}", "#{field} must be a non-negative number.") if parsed.negative?

      parsed
    rescue ArgumentError, TypeError
      error("invalid_#{field}", "#{field} must be a non-negative number.")
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      error("invalid_date", "date must be in YYYY-MM-DD format.")
    end

    def validate_tag_ids(params)
      return nil unless params.key?("tag_ids")

      tag_ids = Array(params["tag_ids"]).map(&:to_s).reject(&:blank?)
      return error("invalid_tags", "One or more tag_ids do not belong to the user's family.") unless family.tags.where(id: tag_ids).count == tag_ids.uniq.size

      tag_ids
    end

    def serialize(transfer)
      outflow_entry = transfer.outflow_transaction.entry
      inflow_entry = transfer.inflow_transaction.entry

      {
        id: transfer.id,
        date: outflow_entry.date,
        status: transfer.status,
        kind: transfer.outflow_transaction.kind,
        source: {
          account: outflow_entry.account.name,
          transaction_id: transfer.outflow_transaction.id,
          amount: outflow_entry.amount.abs,
          currency: outflow_entry.currency
        },
        destination: {
          account: inflow_entry.account.name,
          transaction_id: transfer.inflow_transaction.id,
          amount: inflow_entry.amount.abs,
          currency: inflow_entry.currency
        },
        fees: transfer.fee_transactions.map do |fee|
          {
            transaction_id: fee.id,
            account: fee.entry.account.name,
            amount: fee.entry.amount.abs,
            currency: fee.entry.currency
          }
        end,
        tags: transfer.outflow_transaction.tags.map { |tag| { id: tag.id, name: tag.name } }
      }
    end

    def error_response?(value)
      value.is_a?(Hash) && value[:success] == false
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
