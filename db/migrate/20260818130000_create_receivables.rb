class CreateReceivables < ActiveRecord::Migration[7.2]
  def change
    create_table :receivables, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :debtor_name
      t.string :debtor_contact
      t.decimal :interest_rate, precision: 10, scale: 3
      t.string :rate_type, default: "fixed"
      t.integer :term_months
      t.string :payment_frequency, null: false, default: "monthly"
      t.date :start_date
      t.decimal :initial_balance, precision: 19, scale: 4
      t.string :subtype
      t.text :notes
      t.jsonb :locked_attributes, default: {}
      t.timestamps
    end

    create_table :receivable_installments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :receivable, null: false, foreign_key: true, type: :uuid
      t.integer :number, null: false
      t.date :due_date, null: false
      t.decimal :principal_amount, precision: 19, scale: 4, null: false, default: 0
      t.decimal :interest_amount, precision: 19, scale: 4, null: false, default: 0
      t.decimal :total_amount, precision: 19, scale: 4, null: false, default: 0
      t.decimal :paid_amount, precision: 19, scale: 4, null: false, default: 0
      t.string :status, null: false, default: "pending"
      t.date :paid_at
      t.timestamps

      t.index [ :receivable_id, :number ], unique: true
      t.index [ :receivable_id, :due_date ]
    end

    create_table :receivable_payments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :receivable_installment, null: false, foreign_key: true, type: :uuid
      t.references :transaction, null: false, foreign_key: true, type: :uuid
      t.decimal :amount_applied, precision: 19, scale: 4, null: false
      t.timestamps
    end
  end
end
