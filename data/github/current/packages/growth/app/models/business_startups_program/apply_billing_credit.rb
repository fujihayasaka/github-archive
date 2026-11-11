# typed: strict
# frozen_string_literal: true

# Applies discount credit to a business that has been accepted into the GitHub for Startups program
#
# This uses the Billing Platform API to create a discount credit with the GitHubForStartups funding source.
# The discount is applied at the enterprise level and will reduce billing charges over the specified duration.
#
# Example usage:
#   result = BusinessStartupsProgram::ApplyBillingCredit.perform(
#     business: business,
#     amount: Billing::Money.parse("$10000.00"),
#     start_date: Time.current,
#     end_date: 1.year.from_now
#   )
#
#   if result[:success]
#     # Discount credit applied successfully
#   else
#     # Handle error: result[:error_message]
#   end
class BusinessStartupsProgram::ApplyBillingCredit
  include ActiveModel::Validations

  validates :business, presence: true
  validates :amount, presence: true, numericality: { greater_than: 0, less_than: 10_001 }
  validates :start_date, presence: true
  validates :end_date, presence: true
  validate :business_has_customer
  validate :business_in_startups_program
  validate :end_date_after_start_date

  # Public: Applies discount credit to a business in the GitHub for Startups program
  #
  # business - the Business to apply the discount to
  # amount - the Billing::Money amount of the discount
  # start_date - Time when the discount becomes active
  # end_date - Time when the discount expires
  #
  # Returns a result hash with :success and either :discount_uuid or :error_message
  sig do
    params(
      business: T.nilable(Business),
      amount: T.nilable(Billing::Money),
      start_date: T.nilable(Time),
      end_date: T.nilable(Time),
    ).returns(T::Hash[Symbol, T.untyped])
  end
  def self.perform(business:, amount:, start_date:, end_date:)
    new(
      business: business,
      amount: amount,
      start_date: start_date,
      end_date: end_date,
    ).perform
  end

  # Initialize a new ApplyBillingCredit
  #
  # business - the Business whose credit balance is being increased
  # amount - the Billing::Money amount to apply to the credit balance
  # start_date - Time when the discount becomes active
  # end_date - Time when the discount expires
  sig do
    params(
      business: T.nilable(Business),
      amount: T.nilable(Billing::Money),
      start_date: T.nilable(Time),
      end_date: T.nilable(Time),
    ).void
  end
  def initialize(business:, amount:, start_date:, end_date:)
    @business = business
    @amount = amount
    @start_date = start_date
    @end_date = end_date
  end

  # Public: Applies discount credit to the business
  sig { returns T::Hash[Symbol, T.untyped] }
  def perform
    if valid?
      apply_discount_credit
    else
      error_sentence = errors.full_messages.to_sentence
      { success: false, error_message: error_sentence }
    end
  end

  private

  sig { returns T.nilable(Business) }
  attr_reader :business

  sig { returns T.nilable(Billing::Money) }
  attr_reader :amount

  sig { returns T.nilable(Time) }
  attr_reader :start_date

  sig { returns T.nilable(Time) }
  attr_reader :end_date

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def apply_discount_credit
    response = create_discount

    if response.is_a?(Billing::Platform::Api::Error)
      return handle_api_error(response)
    end

    discount_uuid = response.dig(:discount, :uuid)

    GitHub.instrument("billing.credits_create", audit_log_payload.merge(actor: self.class.name))

    { success: true, discount_uuid: discount_uuid }
  end

  sig { params(error: Billing::Platform::Api::Error).returns(T::Hash[Symbol, T.untyped]) }
  def handle_api_error(error)
    original_message = extract_original_error_message(error)

    GitHub.logger.error(
      "Failed to create discount credit via Billing Platform",
      error_class: error.class.name,
      error_message: error.message,
      original_error_message: original_message,
    )

    user_message = if original_message
      "Unable to create discount credit: #{original_message}"
    else
      "Unable to create discount credit at this time. Please try again later."
    end

    { success: false, error_message: user_message }
  end

  sig { params(error: Billing::Platform::Api::Error).returns(T.nilable(String)) }
  def extract_original_error_message(error)
    return unless error.respond_to?(:original_error)

    original = error.original_error
    original&.message if original.respond_to?(:message)
  end

  sig { returns(T.untyped) }
  def create_discount
    customer_id = T.must(business).customer_id.to_s

    Billing::Platform::Api::Client.new.create_discount(
      discount: {
        customerId: customer_id,
        startDate: T.must(start_date).to_i,
        endDate: T.must(end_date).to_i,
        targetAmount: T.must(amount).dollars.to_f,
        percentage: 0,
        discountType: BillingPlatform::Api::V1::DiscountType::FixedAmount,
        fundingSource: BillingPlatform::Api::V1::FundingSource::GitHubForStartups,
        targets: [{ id: customer_id, type: "EnterpriseDiscount" }],
      },
    )
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def audit_log_payload
    customer_id = T.must(business).customer_id.to_s

    {
      business: T.must(business),
      customer_id: customer_id,
      targets: [{ id: customer_id, type: "EnterpriseDiscount" }],
      discount_amount: T.must(amount).dollars,
      percentage: 0,
      discount_type: "FixedAmount",
      start_date: T.must(start_date).strftime("%Y-%m-%d %H:%M:%S"),
      end_date: T.must(end_date).strftime("%Y-%m-%d %H:%M:%S"),
      funding_source: "GitHubForStartups",
    }
  end

  sig { void }
  def business_has_customer
    unless business&.customer&.present?
      errors.add(:business, "must have a customer")
    end
  end

  sig { void }
  def business_in_startups_program
    unless business&.startups_program&.currently_in_the_program?
      errors.add(:business, "must be in the startups program")
    end
  end

  sig { void }
  def end_date_after_start_date
    if start_date.present? && end_date.present? && T.must(end_date) <= T.must(start_date)
      errors.add(:end_date, "must be after start date")
    end
  end
end
