class AddRecurringTransactionToTransactions < ActiveRecord::Migration[7.2]
  def change
    add_reference :transactions, :recurring_transaction, type: :uuid, null: true,
                  foreign_key: { on_delete: :nullify }, index: true
  end
end
