# typed: strict
# frozen_string_literal: true

# Represents the method by which a user or a business is paying for GitHub and includes a
# flattening of billing details like address information and payment
# instruments (credit card).
class PaymentMethod < ApplicationRecord::Domain::Users

  include GitHub::UTF8
  include GitHub::Validations
  include GitHub::Memoizer
  include Instrumentation::Model
  include PaymentMethod::CreditCardDependency
  include PaymentMethod::PaypalDependency
  include PaymentMethod::InstrumentationDependency

  class ReusedCardFingerprintResult < T::Struct
    prop :card_fingerprint, String
    prop :count, Integer
  end

  # Public: User/Organization that uses this card to pay for GitHub.
  belongs_to :user

  # Public: Customer that owns this payment method.
  belongs_to :customer, touch: true

  belongs_to :manually_reviewed_by, class_name: "User"

  scope :for_purpose, -> (purpose) do
    if purpose == :sponsors
      joins(:customer).merge(Customer.sponsors_purpose)
    else
      base_query = left_joins(:customer)
      base_query.where.not(customers: { purpose: :sponsors })
        .or(base_query.where(customers: { id: nil }))
    end
  end

  # A payment should belong to a user or customer
  before_save :validate_presence_of_user_or_customer
  after_commit :update_rbi_auto_pay_on_country_change, on: :update,
    if: [:saved_change_to_country?]

  after_destroy :instrument_clear

  # Public: String customer identifier for the user's or business's record in the payment
  # processors system.
  # column :payment_processor_customer_id
  validates_presence_of :payment_processor_customer_id

  # Public: The payment processor. See GitHub::Billing::PaymentProcessors
  # column :payment_processor_type
  sig { returns(GitHub::Billing::PaymentProcessors::PaymentProcessor) }
  memoize def payment_processor
    GitHub::Billing::PaymentProcessors.create(
        payment_processor_type,
        payment_processor_customer_id,
        gateway: ::Billing::Zuora::PaymentGateway.new(user),
    )
  end

  # Public: Boolean if this is the User's or Business's primary payment method.
  # column :primary

  PAYMENT_TOKEN_CLEARED = "payment-token-cleared"
  INDIA_COUNTRY_CODE = "IND"
  JAPAN_COUNTRY_CODE = "JPN"

  # Public: String token representing the default payment method and providing
  # the ability to make a sale against this payment instrument.
  # column :payment_token
  validates_presence_of :payment_token

  # Public: Boolean if the payment_token is valid.
  sig { returns(T::Boolean) }
  def valid_payment_token?
    !!(payment_token.present? && payment_token != PAYMENT_TOKEN_CLEARED)
  end

  # Public: Billing address country in ISO 3166-1 alpha-3 format.
  # column :country
  validates_length_of :country, is: 3, allow_blank: true
  validates :country, unicode3: true

  # column :region
  validates :region, unicode3: true
  # column :postal_code
  validates :postal_code, unicode3: true

  # Public: Integer number of expiration reminders sent. This only applies to
  # credit cards (default: 0).
  # column :expiration_reminders

  # Public: User or Business supplied fields, not to be persisted
  sig { returns(T.nilable(String)) }
  attr_accessor :card_number
  sig { returns(T.nilable(String)) }
  attr_accessor :cvv
  sig { returns(T.nilable(String)) }
  attr_accessor :paypal_nonce
  sig { returns(T.nilable(String)) }
  attr_accessor :encrypted_expiration_month
  sig { returns(T.nilable(String)) }
  attr_accessor :encrypted_expiration_year

  # Public: PaymentMethods that are credit cards that are expiring next month.
  scope :expiring_credit_cards, lambda {
    one_month_from_now = GitHub::Billing.today + 1.month

    where("`primary` = 1
      AND truncated_number IS NOT NULL
      AND expiration_reminders = 0
      AND expiration_year = ?
      AND expiration_month = ?",
      one_month_from_now.year,
      one_month_from_now.month,
    )
  }

  # Public: Send out credit card expiring reminders for cards on file that will
  # expire in the next three weeks.
  sig { void }
  def self.send_expiring_credit_card_reminders
    PaymentMethod.expiring_credit_cards.includes(:user, customer: :business).find_each do |credit_card|
      if owner = T.let(credit_card, PaymentMethod).owner
        BillingExpiringCardReminderJob.perform_later(owner)
      end
    end
  end

  sig { returns(String) }
  def self.zuora_processor_slug
    GitHub::Billing::PaymentProcessors::ZuoraProcessor::SLUG
  end

  sig { returns(String) }
  def self.braintree_processor_slug
    GitHub::Billing::PaymentProcessors::BraintreeProcessor::SLUG
  end

  sig { params(index: String).returns(T.untyped) }
  def self.use_index(index)
    from("#{self.table_name} USE INDEX(#{index})")
  end

  # @param card_fingerprint [String] The card fingerprint to lookup. Can be a Stripe token or a PayPal email.
  # @returns [PaymentMethod] The payment methods that matches the card fingerprint.
  sig { params(card_fingerprint: String).returns(ActiveRecord::Relation) }
  def self.with_card_fingerprint(card_fingerprint)
    PaymentMethod.use_index("idx_pm_card_fingerprint_user_id_manually_reviewed_created_at_id").where(card_fingerprint: card_fingerprint)
  end

  sig { params(threshold: Integer).returns(T::Array[PaymentMethod::ReusedCardFingerprintResult]) }
  def self.with_card_fingerprint_reuse_over_threshold_in_last_30_days(threshold: 5)
    PaymentMethod.use_index("idx_pm_card_fingerprint_user_id_manually_reviewed_created_at_id")
      .where.not(card_fingerprint: nil)
      .where(user: User.not_suspended)
      .where(manually_reviewed_at: nil)
      .where(created_at: 30.days.ago..Time.now)
      .select(:id, :card_fingerprint)
      .group(:card_fingerprint)
      .having("count_id >= :threshold", threshold: threshold)
      .order("count_id DESC")
      .count(:id)
      .map do |(card_fingerprint, count)|
        PaymentMethod::ReusedCardFingerprintResult.new(
          card_fingerprint: card_fingerprint,
          count: count,
        )
      end
  end

  sig { returns(T.nilable(Billing::Types::Account)) }
  def owner
    # We have validation that user or customer must exist but
    # we don't validate that the business on the customer exists
    user || T.must(customer).business
  end


  sig { returns(T::Boolean) }
  def manually_reviewed?
    manually_reviewed_at.present? || manually_reviewed_by_id.present?
  end

  # Public: Populates PaymentMethod from the User or Business entry from the payment forms.
  #
  # details - A Hash of payment details:
  #   :charge        - Boolean whether to attempt a recurring charge with this update. Default: true
  #   :billing_extra - String extra billing information.
  #   :paypal_nonce  - String nonce representing a paypal account (optional).
  #   :credit_card   - A Hash of potentially encrypted CC info, including:
  #     * :number           - CC number as a String.
  #     * :expiration_month - Expiration month as a String of form MM
  #     * :expiration_year  - Expiration year as a String of form YY
  #     * :cvv              - CVV as a String (e.g. "420")
  #   :billing_address  - The billing address as a Hash of optionally encrypted CC info
  #     * :country_code_alpha3 - Country as a String
  #     * :region              - Region as a String
  #     * :postal_code         - Postal code as a String
  #
  sig { params(details: T::Hash[Symbol, T.untyped]).returns(PaymentMethod) }
  def self.build_from_payment_details(details)
    card    = details[:credit_card] || {}
    address = details[:billing_address] || {}

    payment_method = PaymentMethod.new

    payment_method.country                    = address[:country_code_alpha3]
    payment_method.region                     = address[:region]
    payment_method.postal_code                = address[:postal_code]
    payment_method.card_number                = card[:number]
    payment_method.cvv                        = card[:cvv]
    payment_method.encrypted_expiration_month = card[:expiration_month]
    payment_method.encrypted_expiration_year  = card[:expiration_year]
    payment_method.paypal_nonce               = details[:paypal_nonce]

    payment_method
  end

  # Public: Update payment details.
  #
  # details - A Hash of payment details that includes:
  #           :credit_card     - A Hash of credit card info.
  #           :paypal_nonce    - A String nonce from PayPal.
  #           :billing_address - A Hash of billing address info (usually used with CC)
  #           :actor           - User taking this action.
  #           :zuora_payment_method_id - A Zuora HPM provided payment method ID
  sig { params(details: T::Hash[Symbol, T.untyped]).returns(GitHub::Billing::Result) }
  def update_payment_details(details)
    raise ArgumentError if details.blank?

    card    = details[:credit_card] || {}
    address = details[:billing_address] || {}
    actor   = details[:actor] || user
    target = T.must(owner)
    auto_pay = details[:auto_pay].nil? ? true : details[:auto_pay]

    populate_address(address)

    payment_details = GitHub::Billing::PaymentProcessorPaymentDetails.new \
      token: payment_token,
      login: actor.login,
      has_card_on_file: credit_card?,
      paypal_nonce: details[:paypal_nonce],
      card_number: card[:number],
      expiration_month: card[:expiration_month],
      expiration_year: card[:expiration_year],
      cvv: card[:cvv],
      country_code_alpha3: address[:country_code_alpha3],
      region: address[:region],
      postal_code: address[:postal_code],
      zuora_payment_method_id: details[:zuora_payment_method_id],
      email: target.payment_processor_email,
      account_name: target.payment_processor_account_name,
      auto_pay: auto_pay

    lock do
      result = payment_processor.update_payment_details(payment_details) do |record|
        populate_from_record(record)
        save!
        instrument_update(actor)
      end
      instrument_update_failure(actor, result.error_message) unless result.success?
      result
    end
  end

  # Public: Assign values from the given Zuora payment method without saving this record.
  sig { params(zuora_payment_method: Billing::Zuora::PaymentMethod).void }
  def assign_from_zuora_payment_method(zuora_payment_method)
    self.truncated_number = zuora_payment_method.masked_number
    self.expiration_month = zuora_payment_method.expiration_month
    self.expiration_year = zuora_payment_method.expiration_year
    self.card_type = zuora_payment_method.card_type
    self.unique_number_identifier = zuora_payment_method.fingerprint
  end

  sig { returns(T::Boolean) }
  def blocklisted?
    !!BlacklistedPaymentMethod.find_by_payment_method(self)
  end

  # Public: Clears all payment details. It will no longer be possible to
  # process payment for this customer.
  sig { params(actor: T.nilable(User)).returns(T::Boolean) }
  def clear_payment_details(actor)
    if deleted = payment_processor.clear_payment_details
      self.payment_token            = PAYMENT_TOKEN_CLEARED
      self.expiration_reminders     = 0
      self.truncated_number         = nil
      self.expiration_month         = nil
      self.expiration_year          = nil
      self.card_type                = nil
      self.paypal_email             = nil
      self.unique_number_identifier = nil

      self.save!

      instrument_clear(actor:)
    end

    deleted
  end

  # Internal: Populate billing address from a hash.
  #
  # billing_address - A Hash of billing address info:
  #                   :region               - String region.
  #                   :postal_code          - String postal code.
  #                   :country_code_alpha3  - String country.
  sig { params(billing_address: T::Hash[Symbol, T.nilable(String)]).returns(T.self_type) }
  def populate_address(billing_address)
    return self unless billing_address.present?

    self.region      = billing_address[:region]
    self.postal_code = billing_address[:postal_code]
    self.country     = billing_address[:country_code_alpha3]

    self
  end

  # Internal: Populate self with a PaymentProcessorRecord.
  #
  sig { params(record: GitHub::Billing::PaymentProcessorRecord).returns(T.self_type) }
  def populate_from_record(record)
    self.payment_processor_customer_id = record.customer_id

    self.payment_token = record.token
    self.expiration_reminders = 0

    # credit card
    self.truncated_number         = record.masked_number
    self.expiration_month         = record.expiration_month
    self.expiration_year          = record.expiration_year
    self.card_type                = record.card_type
    self.unique_number_identifier = record.unique_number_identifier

    # paypal
    self.paypal_email = record.paypal_email

    self
  end

  # Returns a string summary of this payment method.
  sig { returns(String) }
  def to_s
    return "invalid payment method" unless valid_payment_token?
    return paypal_email.to_s if paypal_email.present?
    "#{card_type} #{formatted_number}"
  end

  # Public: True if this payment method is expiring in the next three weeks.
  sig { returns(T::Boolean) }
  def expiring_in_less_than_three_weeks?
    year = self.expiration_year
    month = self.expiration_month
    return false if year.nil? || month.nil?

    GitHub::Billing.today >= Date.new(year, month) - 3.weeks
  end

  sig { returns(T::Boolean) }
  def on_braintree?
    valid_payment_token? && using_braintree_processor?
  end

  sig { returns(T::Boolean) }
  def on_zuora?
    valid_payment_token? && using_zuora_processor?
  end

  sig { returns(T::Boolean) }
  def using_braintree_processor?
    payment_processor_type == PaymentMethod.braintree_processor_slug
  end

  sig { returns(T::Boolean) }
  def using_zuora_processor?
    payment_processor_type == PaymentMethod.zuora_processor_slug
  end

  sig { returns(T.nilable(Integer)) }
  def external_payment_method_consecutive_failure_count
    external_payment_method&.[]("NumConsecutiveFailures")
  end

  sig { returns(T::Boolean) }
  def from_india?
    country == INDIA_COUNTRY_CODE
  end

  sig { returns(T::Boolean) }
  def from_japan?
    country == JAPAN_COUNTRY_CODE
  end

  # Public: Returns the card fingerprint if one exists. Either the unique_number_identifier or the paypal_email
  sig { returns(T.nilable(String)) }
  def card_fingerprint
    unique_number_identifier || paypal_email
  end

  sig { returns(T::Boolean) }
  def supports_authorization?
    credit_card? || paypal?
  end

  private

  sig { returns(T.nilable(GitHub::Billing::Result)) }
  def update_rbi_auto_pay_on_country_change
    return if from_india?
    user = self.user
    return unless user&.autopay_disabled_by_india_rbi?

    user.enable_auto_pay!(:india_rbi)
  end

  sig { returns(T.nilable(T::Hash[String, T.untyped])) }
  def external_payment_method
    return unless valid_payment_token?
    GitHub.zuorest_client.get_payment_method(payment_token)
  end

  sig { void }
  def validate_presence_of_user_or_customer
    unless customer || user
      raise ActiveRecord::RecordInvalid.new(self)
    end
  end

  # Private: Semaphore lock for ensuring that actions don't happen concurrently.
  #
  # Takes a block to be called within the semaphore.
  #
  # Returns what the block returns or a failed
  # GitHub::Billing::Result if the lock cannot be obtained.
  sig { params(blk: T.proc.returns(GitHub::Billing::Result)).returns(GitHub::Billing::Result) }
  def lock(&blk)
    mutex = GitHub::Redis::Mutex.new(T.must(customer).update_payment_method_key)
    begin
      mutex.lock { yield }
    rescue GitHub::Redis::Mutex::LockError
      GitHub::Billing::Result.failure "Your payment details are updating. Please check your billing settings for results."
    end
  end
end
