# Builds the amortization schedule for a receivable (French system, fixed
# payment, monthly frequency only). Regeneration keeps installments that
# already have payments applied and re-amortizes the remaining principal
# over the remaining term.
class Receivable::InstallmentGenerator
  attr_reader :receivable

  def initialize(receivable)
    @receivable = receivable
  end

  def generate
    ActiveRecord::Base.transaction do
      kept = receivable.installments.where("paid_amount > 0").order(:number).to_a
      receivable.installments.where(paid_amount: 0).destroy_all

      next if receivable.term_months.blank?

      principal = receivable.original_balance.amount.to_d
      next unless principal.positive?

      remaining_principal = (principal - kept.sum(&:principal_amount)).round(2)
      remaining_terms = receivable.term_months - kept.size
      next if remaining_terms <= 0 || !remaining_principal.positive?

      monthly_rate = (receivable.interest_rate || 0).to_d / 100 / 12
      payment = fixed_payment(remaining_principal, monthly_rate, remaining_terms)

      start_number = kept.size
      balance = remaining_principal

      (1..remaining_terms).each do |i|
        number = start_number + i
        interest = (balance * monthly_rate).round(2)
        principal_part = i == remaining_terms ? balance : [ (payment - interest).round(2), balance ].min

        receivable.installments.create!(
          number: number,
          due_date: schedule_base_date + number.months,
          principal_amount: principal_part,
          interest_amount: interest,
          total_amount: (principal_part + interest).round(2)
        )

        balance = (balance - principal_part).round(2)
      end
    end
  end

  private
    def fixed_payment(principal, monthly_rate, terms)
      return (principal / terms).round(2) if monthly_rate.zero?

      factor = (1 + monthly_rate)**terms
      ((principal * monthly_rate * factor) / (factor - 1)).round(2)
    end

    def schedule_base_date
      receivable.start_date || receivable.created_at&.to_date || Date.current
    end
end
