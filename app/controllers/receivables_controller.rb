class ReceivablesController < ApplicationController
  include AccountableResource

  permitted_accountable_attributes(
    :id, :subtype, :debtor_name, :debtor_contact, :interest_rate, :term_months,
    :start_date, :initial_balance, :notes
  )

  before_action :set_payment_account, only: [ :new_payment, :create_payment ]

  def new_payment
  end

  def create_payment
    amount = payment_params[:amount].to_d
    date = begin
      payment_params[:date].presence&.to_date
    rescue Date::Error
      nil
    end || Date.current

    if amount <= 0
      redirect_to account_path(@account), alert: t("receivables.payments.invalid_amount")
      return
    end

    transaction = if payment_params[:destination_account_id].present?
      destination_account = Current.user.accessible_accounts.find(payment_params[:destination_account_id])
      return unless require_account_permission!(destination_account)

      transfer = Transfer::Creator.new(
        family: Current.family,
        source_account_id: @account.id,
        destination_account_id: destination_account.id,
        date: date,
        amount: amount
      ).create
      transfer.outflow_transaction
    else
      entry = @account.entries.create!(
        name: t("receivables.payments.entry_name", debtor: @account.receivable.debtor_name),
        date: date,
        amount: amount,
        currency: @account.currency,
        entryable: Transaction.new(kind: "funds_movement")
      )
      entry.sync_account_later
      entry.transaction
    end

    Receivable::PaymentApplicator.new(@account.receivable).apply(transaction, amount: amount)

    redirect_to account_path(@account), notice: t("receivables.payments.created")
  end

  private
    def set_payment_account
      @account = Current.user.accessible_accounts.find(params[:id])
      require_account_permission!(@account)
    end

    def payment_params
      params.require(:payment).permit(:amount, :date, :destination_account_id)
    end
end
