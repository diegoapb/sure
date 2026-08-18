class Assistant::Function::DeleteRecurringTransaction < Assistant::Function
  class << self
    def name
      "delete_recurring_transaction"
    end

    def description
      <<~INSTRUCTIONS
        Permanently deletes a recurring transaction pattern.

        Real transactions are NOT affected — only the expected pattern and its
        projections are removed. This action cannot be undone, so confirm with the
        user before deleting; if they only want to stop future projections, prefer
        pause_recurring_transaction instead.
        Identify the pattern by its id — use get_recurring_transactions to find it.
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
        }
      }
    )
  end

  def call(params = {})
    recurring_transaction = find_recurring_transaction(params["id"])
    return error("not_found", "Recurring transaction with id '#{params["id"]}' not found.") unless recurring_transaction

    name = recurring_transaction.merchant&.name || recurring_transaction.name
    recurring_transaction.destroy!

    {
      success: true,
      recurring_transaction: { id: recurring_transaction.id, name: name },
      message: "Recurring transaction '#{name}' deleted. Real transactions were not affected."
    }
  end

  private
    def find_recurring_transaction(id)
      return nil unless valid_uuid?(id)
      family.recurring_transactions.accessible_by(user).find_by(id: id)
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
