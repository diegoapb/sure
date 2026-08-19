class Receivable < ApplicationRecord
  include Accountable

  SUBTYPES = {
    "personal_loan" => { short: "Personal Loan", long: "Personal Loan" },
    "sale_credit" => { short: "Sale on Credit", long: "Sale on Credit" },
    "rent" => { short: "Rent", long: "Rent Receivable" },
    "services" => { short: "Services", long: "Professional Services" },
    "other" => { short: "Other", long: "Other Receivable" }
  }.freeze

  PAYMENT_FREQUENCIES = %w[monthly].freeze

  has_many :installments, -> { order(:number) }, class_name: "ReceivableInstallment", dependent: :destroy

  validates :debtor_name, presence: true
  validates :subtype, inclusion: { in: SUBTYPES.keys }, allow_blank: true
  validates :payment_frequency, inclusion: { in: PAYMENT_FREQUENCIES }
  validates :interest_rate, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :term_months, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  after_create_commit :generate_installments
  after_update_commit :regenerate_installments, if: :schedule_changed?

  # Nominal annual rate divided by 12, mirroring Loan#monthly_payment
  def monthly_payment
    return nil if term_months.nil? || original_balance.amount.zero?

    monthly_rate = (interest_rate || 0) / 100.0 / 12.0

    payment = if monthly_rate.zero?
      original_balance.amount / term_months
    else
      (original_balance.amount * monthly_rate * (1 + monthly_rate)**term_months) / ((1 + monthly_rate)**term_months - 1)
    end

    Money.new(payment.round(2), currency)
  end

  def original_balance
    amount = initial_balance || account&.first_valuation_amount || 0
    Money.new(amount, currency)
  end

  def paid_total
    Money.new(installments.sum(:paid_amount), currency)
  end

  def next_installment
    installments.where.not(status: "paid").order(:due_date).first
  end

  def overdue_installments
    installments.where.not(status: "paid").where(due_date: ...Date.current)
  end

  def generate_installments
    Receivable::InstallmentGenerator.new(self).generate
  end

  def currency
    account&.currency || Money.default_currency.iso_code
  end

  class << self
    def color
      "#12B76A"
    end

    def icon
      "hand-coins"
    end

    def classification
      "asset"
    end
  end

  private
    def schedule_changed?
      (saved_changes.keys & %w[interest_rate term_months start_date initial_balance]).any?
    end

    def regenerate_installments
      Receivable::InstallmentGenerator.new(self).generate
    end
end
