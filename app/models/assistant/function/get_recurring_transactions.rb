class Assistant::Function::GetRecurringTransactions < Assistant::Function
  class << self
    def default_page_size
      50
    end

    def name
      "get_recurring_transactions"
    end

    def description
      <<~INSTRUCTIONS
        Returns recurring transaction patterns for the user's family (subscriptions,
        rent, salaries, etc.), sorted by next expected date, with pagination.

        A recurring transaction is an *expected pattern*, not a real transaction:
        it projects an amount on a given day of the month and tracks whether the
        real charge arrived. Use this before create_recurring_transaction to avoid
        creating duplicates.

        Note on pagination:

        This function can be paginated. You can expect the following properties in the response:

        - `total_pages`: The total number of pages of results
        - `page`: The current page of results
        - `page_size`: The number of results per page (this will always be #{default_page_size})
        - `total_results`: The total number of results
      INSTRUCTIONS
    end
  end

  def strict_mode?
    false
  end

  def params_schema
    build_schema(
      required: [],
      properties: {
        status: {
          type: "string",
          description: "Filter by status (defaults to all)",
          enum: [ "active", "inactive" ]
        },
        page: {
          type: "integer",
          description: "Page number (defaults to 1)"
        }
      }
    )
  end

  def call(params = {})
    scope = family.recurring_transactions
      .accessible_by(user)
      .includes(:account, :merchant, :destination_account)
      .order(status: :asc, next_expected_date: :asc)
    scope = scope.where(status: params["status"]) if params["status"].present?

    pagy = Pagy.new(count: scope.count, page: params["page"] || 1, limit: default_page_size)
    recurring_transactions = scope.offset(pagy.offset).limit(pagy.limit)

    {
      recurring_transactions: recurring_transactions.map { |rt| serialize(rt) },
      total_results: pagy.count,
      page: pagy.page,
      page_size: default_page_size,
      total_pages: pagy.pages
    }
  end

  private
    def default_page_size
      self.class.default_page_size
    end

    def serialize(rt)
      {
        id: rt.id,
        name: rt.merchant&.name || rt.name,
        merchant: rt.merchant&.name,
        amount: rt.amount_money&.format,
        currency: rt.currency,
        expected_amount_min: rt.expected_amount_min_money&.format,
        expected_amount_max: rt.expected_amount_max_money&.format,
        expected_day_of_month: rt.expected_day_of_month,
        next_expected_date: rt.next_expected_date,
        last_occurrence_date: rt.last_occurrence_date,
        status: rt.status,
        account: rt.account&.name,
        destination_account: rt.destination_account&.name,
        transfer: rt.transfer?,
        manual: rt.manual?
      }
    end
end
