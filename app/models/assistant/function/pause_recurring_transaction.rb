class Assistant::Function::PauseRecurringTransaction < Assistant::Function
  class << self
    def name
      "pause_recurring_transaction"
    end

    def description
      <<~INSTRUCTIONS
        Pauses (deactivates) a recurring transaction pattern, e.g. when the user
        cancels a subscription but wants to keep its history.

        A paused pattern stops projecting upcoming charges but is kept and can be
        resumed later with update_recurring_transaction (status: "active").
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
    return error("already_paused", "Recurring transaction '#{display_name(recurring_transaction)}' is already paused.") if recurring_transaction.inactive?

    recurring_transaction.mark_inactive!

    {
      success: true,
      recurring_transaction: { id: recurring_transaction.id, name: display_name(recurring_transaction), status: recurring_transaction.status },
      message: "Recurring transaction '#{display_name(recurring_transaction)}' paused. It can be resumed with update_recurring_transaction."
    }
  end

  private
    def find_recurring_transaction(id)
      return nil unless valid_uuid?(id)
      family.recurring_transactions.accessible_by(user).find_by(id: id)
    end

    def display_name(rt)
      rt.merchant&.name || rt.name
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
