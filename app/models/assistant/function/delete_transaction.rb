class Assistant::Function::DeleteTransaction < Assistant::Function
  class << self
    def name
      "delete_transaction"
    end

    def description
      <<~INSTRUCTIONS
        Permanently deletes an existing transaction.

        Use get_transactions first to find the transaction id. This action cannot
        be undone, so confirm with the user before deleting.

        Split child transactions cannot be deleted directly — use the split editor.
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
          description: "Transaction ID from get_transactions"
        }
      }
    )
  end

  def call(params = {})
    transaction = find_transaction(params["id"])
    return error("not_found", "Transaction with id '#{params["id"]}' not found.") unless transaction

    entry = transaction.entry
    return error("split_child", "Split child transactions cannot be deleted directly. Use the split editor.") if entry.split_child?
    return error("not_authorized", "You do not have permission to delete this transaction.") unless permitted_to_delete?(entry.account)

    entry.destroy!
    entry.sync_account_later

    {
      success: true,
      transaction: serialize(entry),
      message: "Transaction '#{entry.name}' deleted."
    }
  end

  private
    def find_transaction(id)
      return nil unless valid_uuid?(id)

      family.transactions
        .joins(:entry)
        .where(entries: { account_id: user.accessible_accounts.visible.select(:id) })
        .find_by(id: id)
    end

    def permitted_to_delete?(account)
      account.permission_for(user).in?([ :owner, :full_control ])
    end

    def serialize(entry)
      {
        id: entry.entryable_id,
        name: entry.name,
        date: entry.date,
        account: entry.account.name
      }
    end

    def error(key, message)
      { success: false, error: key, message: message }
    end
end
