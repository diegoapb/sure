require "test_helper"

class RecurringTransaction::ScheduleTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:dylan_family)
    @family.recurring_transactions.destroy_all

    @recurring = RecurringTransaction.create!(
      family: @family,
      account: accounts(:depository),
      merchant: merchants(:netflix),
      amount: 15.99,
      currency: "USD",
      expected_day_of_month: 15,
      last_occurrence_date: 2.months.ago.to_date,
      next_expected_date: Date.current.beginning_of_month.change(day: 15),
      status: "active",
      occurrence_count: 2
    )
  end

  test "builds one occurrence per pattern per month with clamped due date" do
    @recurring.update!(expected_day_of_month: 31)

    february = Date.new(2026, 2, 1)
    schedule = RecurringTransaction::Schedule.new([ @recurring ], from: february, to: february.end_of_month)

    assert_equal 1, schedule.occurrences.size
    assert_equal Date.new(2026, 2, 28), schedule.occurrences.first.due_date
  end

  test "occurrence is executed when a linked transaction exists in the month" do
    month = Date.current.beginning_of_month
    entry = create_transaction(account: accounts(:depository), amount: 20, date: month.change(day: 10), name: "Netflix charge")
    entry.entryable.update!(recurring_transaction: @recurring)

    schedule = RecurringTransaction::Schedule.new([ @recurring ], from: month, to: month.end_of_month)
    occurrence = schedule.occurrences.first

    assert occurrence.executed?
    assert_equal entry, occurrence.entry
  end

  test "occurrence is executed when a heuristic match exists in the month" do
    month = Date.current.beginning_of_month
    entry = create_transaction(
      account: accounts(:depository),
      amount: 15.99,
      date: month.change(day: 14),
      merchant: merchants(:netflix)
    )

    schedule = RecurringTransaction::Schedule.new([ @recurring ], from: month, to: month.end_of_month)
    occurrence = schedule.occurrences.first

    assert occurrence.executed?
    assert_equal entry, occurrence.entry
  end

  test "heuristic match is ignored when the entry is claimed by another pattern" do
    month = Date.current.beginning_of_month
    other = RecurringTransaction.create!(
      family: @family,
      name: "Other pattern",
      amount: 15.99,
      currency: "USD",
      expected_day_of_month: 14,
      last_occurrence_date: 1.month.ago.to_date,
      next_expected_date: 1.month.from_now.to_date,
      status: "active",
      occurrence_count: 1
    )

    entry = create_transaction(
      account: accounts(:depository),
      amount: 15.99,
      date: month.change(day: 14),
      merchant: merchants(:netflix)
    )
    entry.entryable.update!(recurring_transaction: other)

    schedule = RecurringTransaction::Schedule.new([ @recurring ], from: month, to: month.end_of_month)

    assert_not schedule.occurrences.first.executed?
  end

  test "occurrence is pending when due in the future and overdue when due in the past" do
    travel_to Date.new(2026, 8, 10) do
      month = Date.new(2026, 8, 1)

      @recurring.update!(expected_day_of_month: 20)
      pending_schedule = RecurringTransaction::Schedule.new([ @recurring ], from: month, to: month.end_of_month)
      assert pending_schedule.occurrences.first.pending?

      @recurring.update!(expected_day_of_month: 5)
      overdue_schedule = RecurringTransaction::Schedule.new([ @recurring ], from: month, to: month.end_of_month)
      assert overdue_schedule.occurrences.first.overdue?
    end
  end
end
