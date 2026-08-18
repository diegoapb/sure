class RecurringTransactionsController < ApplicationController
  before_action :set_recurring_transaction, only: %i[edit update toggle_status destroy match create_match]
  before_action :set_form_options, only: %i[new create edit update]

  def index
    @view = params[:view] == "calendar" ? "calendar" : "list"
    @current_month = current_month
    @family = Current.family

    scope = Current.family.recurring_transactions
                   .accessible_by(Current.user)
                   .includes(:merchant, :account, :destination_account)

    @recurring_transactions = scope.order(status: :asc, next_expected_date: :asc)
    @inactive_recurring_transactions = @recurring_transactions.select(&:inactive?)

    @schedule = RecurringTransaction::Schedule.new(
      scope.active,
      from: @current_month,
      to: @current_month.end_of_month
    )

    @breadcrumbs = [ [ t("breadcrumbs.home"), root_path ], [ t("recurring_transactions.title"), nil ] ]
  end

  def new
    @recurring_transaction = Current.family.recurring_transactions.new(
      currency: Current.family.currency,
      expected_day_of_month: Date.current.day
    )
  end

  def create
    @recurring_transaction = RecurringTransaction.build_manual(
      family: Current.family,
      amount: signed_amount,
      expected_day_of_month: recurring_transaction_params[:expected_day_of_month].to_i,
      merchant: selected_merchant,
      name: recurring_transaction_params[:name].presence,
      account: selected_account,
      currency: recurring_transaction_params[:currency].presence,
      expected_amount_min: variance_range.first,
      expected_amount_max: variance_range.last
    )

    if @recurring_transaction.save
      redirect_back_to_index notice: t("recurring_transactions.created")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @recurring_transaction.assign_attributes(
      amount: signed_amount,
      expected_day_of_month: recurring_transaction_params[:expected_day_of_month],
      merchant: selected_merchant,
      name: selected_merchant.present? ? nil : recurring_transaction_params[:name].presence,
      account: selected_account,
      expected_amount_min: variance_range.first,
      expected_amount_max: variance_range.last
    )

    if @recurring_transaction.expected_day_of_month_changed?
      @recurring_transaction.next_expected_date =
        RecurringTransaction.calculate_next_expected_date_from_today(@recurring_transaction.expected_day_of_month)
    end

    if @recurring_transaction.save
      redirect_back_to_index notice: t("recurring_transactions.updated")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Candidate transactions to manually match against an expected occurrence.
  def match
    @due_date = parse_date(params[:due_date]) || @recurring_transaction.next_expected_date
    window = @due_date.beginning_of_month..@due_date.end_of_month

    @candidate_entries = Current.accessible_entries
      .where(entryable_type: "Transaction")
      .where(date: window)
      .where.not(entryable_id: Transaction.where.not(recurring_transaction_id: nil).select(:id))
      .where.not(entryable_id: Transaction.where(kind: Transaction::TRANSFER_KINDS).select(:id))
      .preload(:account, :entryable)
      .order(date: :desc)
      .limit(100)
  end

  def create_match
    entry = Current.accessible_entries.where(entryable_type: "Transaction").find(params[:entry_id])
    @recurring_transaction.link_transaction!(entry.entryable)

    redirect_back_to_index notice: t("recurring_transactions.matched")
  end

  def update_settings
    Current.family.update!(recurring_settings_params)

    redirect_back_to_index notice: t("recurring_transactions.settings_updated")
  end

  def identify
    count = RecurringTransaction.identify_patterns_for!(Current.family)

    redirect_back_to_index notice: t("recurring_transactions.identified", count: count)
  end

  def cleanup
    count = RecurringTransaction.cleanup_stale_for(Current.family)

    redirect_back_to_index notice: t("recurring_transactions.cleaned_up", count: count)
  end

  def toggle_status
    if @recurring_transaction.active?
      @recurring_transaction.mark_inactive!
      message = t("recurring_transactions.marked_inactive")
    else
      @recurring_transaction.mark_active!
      message = t("recurring_transactions.marked_active")
    end

    redirect_back_to_index notice: message
  end

  def destroy
    @recurring_transaction.destroy!

    flash[:notice] = t("recurring_transactions.deleted")
    redirect_back_to_index
  end

  private

    def set_recurring_transaction
      @recurring_transaction = Current.family.recurring_transactions
                                      .accessible_by(Current.user)
                                      .find(params[:id])
    end

    def set_form_options
      @merchants = Current.family.available_merchants_for(Current.user).alphabetically.to_a
      @accounts = Current.user.accessible_accounts.active.alphabetically.to_a
    end

    def recurring_transaction_params
      params.require(:recurring_transaction).permit(
        :name, :merchant_id, :account_id, :amount, :currency, :nature,
        :expected_day_of_month, :expected_amount_min, :expected_amount_max
      )
    end

    # Sure sign convention: positive = expense/outflow, negative = income.
    # The form always submits a positive amount plus a nature toggle.
    def signed_amount
      amount = recurring_transaction_params[:amount].to_d.abs
      recurring_transaction_params[:nature] == "inflow" ? -amount : amount
    end

    # Both bounds are entered unsigned; the nature toggle signs them. For
    # income both become negative, which flips their order, so sort after
    # signing to keep min <= max.
    def variance_range
      min = recurring_transaction_params[:expected_amount_min]
      max = recurring_transaction_params[:expected_amount_max]
      return [ nil, nil ] if min.blank? || max.blank?

      sign = recurring_transaction_params[:nature] == "inflow" ? -1 : 1
      [ min.to_d.abs * sign, max.to_d.abs * sign ].minmax
    end

    def selected_merchant
      return nil if recurring_transaction_params[:merchant_id].blank?

      Current.family.available_merchants_for(Current.user).find_by(id: recurring_transaction_params[:merchant_id])
    end

    def selected_account
      return nil if recurring_transaction_params[:account_id].blank?

      Current.user.accessible_accounts.find_by(id: recurring_transaction_params[:account_id])
    end

    def current_month
      parse_date(params[:month].present? ? "#{params[:month]}-01" : nil)&.beginning_of_month ||
        Date.current.beginning_of_month
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def redirect_back_to_index(notice: nil)
      flash[:notice] = notice if notice
      target = recurring_transactions_path(view: params[:view].presence, month: params[:month].presence)

      respond_to do |format|
        format.html { redirect_to target }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, target) }
      end
    end

    def recurring_settings_params
      { recurring_transactions_disabled: params[:recurring_transactions_disabled] == "true" }
    end
end
