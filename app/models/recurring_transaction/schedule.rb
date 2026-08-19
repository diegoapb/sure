# Projects a set of recurring transactions onto a date window as monthly
# "occurrences", resolving each one to executed / pending / overdue.
#
# An occurrence is executed when a transaction is explicitly linked to the
# pattern in that month (executed from the module or matched manually), or
# when the pattern's matching heuristics find a transaction in that month
# (automatic detection, e.g. synced from a provider).
class RecurringTransaction::Schedule
  Occurrence = Struct.new(:recurring_transaction, :due_date, :entry, :status, keyword_init: true) do
    def executed? = status == :executed
    def pending?  = status == :pending
    def overdue?  = status == :overdue
  end

  attr_reader :period_start, :period_end

  def initialize(recurring_transactions, from:, to:)
    @recurring_transactions = recurring_transactions.to_a
    @period_start = from
    @period_end = to
  end

  def occurrences
    @occurrences ||= build_occurrences.sort_by { |o| [ o.due_date, o.recurring_transaction.display_name.to_s ] }
  end

  def occurrences_by_date
    @occurrences_by_date ||= occurrences.group_by(&:due_date)
  end

  def occurrences_on(date)
    occurrences_by_date.fetch(date, [])
  end

  def executed_count = occurrences.count(&:executed?)
  def pending_count  = occurrences.count { |o| !o.executed? }

  private
    def build_occurrences
      months.flat_map do |month_start|
        @recurring_transactions.filter_map do |recurring_transaction|
          due_date = due_date_for(recurring_transaction, month_start)
          next unless due_date.between?(period_start, period_end)

          entry = occurrence_entry_for(recurring_transaction, month_start)

          status = if entry.present?
            :executed
          elsif due_date >= Date.current
            :pending
          else
            :overdue
          end

          Occurrence.new(
            recurring_transaction: recurring_transaction,
            due_date: due_date,
            entry: entry,
            status: status
          )
        end
      end
    end

    def months
      (period_start.beginning_of_month..period_end).select { |date| date.day == 1 }
    end

    # Expected day clamped to the month's length (e.g. day 31 in February).
    def due_date_for(recurring_transaction, month_start)
      day = [ recurring_transaction.expected_day_of_month, month_start.end_of_month.day ].min
      Date.new(month_start.year, month_start.month, day)
    end

    def occurrence_entry_for(recurring_transaction, month_start)
      linked_entries_by_month[[ recurring_transaction.id, month_start ]]&.first ||
        heuristic_entries_by_month(recurring_transaction)[month_start]&.first
    end

    # Entries of transactions explicitly linked via recurring_transaction_id,
    # preloaded for the whole window in one query.
    def linked_entries_by_month
      @linked_entries_by_month ||= begin
        transactions = Transaction
          .where(recurring_transaction_id: @recurring_transactions.map(&:id))
          .joins(:entry)
          .where(entries: { date: period_start.beginning_of_month..period_end.end_of_month })
          .includes(:entry)

        transactions
          .group_by { |t| [ t.recurring_transaction_id, t.entry.date.beginning_of_month ] }
          .transform_values { |txns| txns.map(&:entry).sort_by(&:date) }
      end
    end

    # Heuristically matched entries (existing `matching_transactions` logic),
    # excluding entries already claimed by a different pattern.
    def heuristic_entries_by_month(recurring_transaction)
      @heuristic_entries ||= {}
      @heuristic_entries[recurring_transaction.id] ||= begin
        window = period_start.beginning_of_month..period_end.end_of_month

        recurring_transaction.matching_transactions
          .select { |entry| window.cover?(entry.date) }
          .reject { |entry| claimed_by_other_pattern?(entry, recurring_transaction) }
          .group_by { |entry| entry.date.beginning_of_month }
      end
    end

    def claimed_by_other_pattern?(entry, recurring_transaction)
      return false unless entry.entryable.is_a?(Transaction)

      other_id = entry.entryable.recurring_transaction_id
      other_id.present? && other_id != recurring_transaction.id
    end
end
