# typed: strict
# frozen_string_literal: true

# Public: Set up invoiced sponsor account. Creates Stripe customer, Zuora account, and Billing::Customer.
# Used for switching a credit card organization to invoiced billing for sponsorships.
class Sponsors::InvoicedSponsorAccountCreator
  extend T::Sig
  include ActiveModel::Validations

  DATADOG_PREFIX = "sponsors.invoiced_sponsor_account_creator"

  validate :ensure_sponsors_enabled
  validate :ensure_customer_does_not_exist
  validate :ensure_valid_address

  validates :org, presence: true
  validates :name, presence: true
  validates :email, format: {
    with: URI::MailTo::EMAIL_REGEXP,
    message: "must be a valid email address",
  }

  AddressHash = T.type_alias { T::Hash[Symbol, String] }

  # Public: Set up invoiced sponsor account. Creates Stripe customer, Zuora account, and Billing::Customer.
  #
  # inputs - a Hash with the following keys:
  #   :org - the Organization the customer is for.
  #   :name - String. The customer's full name or business name.
  #   :email - String. The customer's email address.
  #   :address - a Hash with any subset of the following keys:
  #      :city - String. City, district, suburb, town, or village.
  #      :country - String. Two-letter country code https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2
  #      :line1 - String. Address line 1.
  #      :line2 - String. Address line 2.
  #      :postal_code - String. Zip or Postal Code.
  #      :state - String. State, county, province, or region.
  #
  sig { params(org: Organization, name: String, email: String, address: AddressHash, actor: T.nilable(User)).void }
  def initialize(org:, name:, email:, address:, actor: nil)
    @org     = org
    @name    = name
    @email   = email
    @address = T.let(Address.new(
      line1:       address[:line1]       || "",
      line2:       address[:line2]       || "",
      city:        address[:city]        || "",
      state:       address[:state]       || "",
      postal_code: address[:postal_code] || "",
      country:     address[:country]     || "",
    ), Address)
    @actor = actor
  end

  sig { returns(Organization) }
  attr_reader :org

  sig { returns(String) }
  attr_reader :name, :email

  sig { returns(Address) }
  attr_reader :address

  # Public: Sets an account up for Sponsors invoicing.
  #
  # It is not recommended to call this method directly, as it is prone to intermittent failures. Prefer
  # `call` instead.
  sig { returns(T::Boolean) }
  def setup
    return false unless valid?
    return false unless cancel_existing_sponsorships
    return false unless close_zuora_subscription

    org_profile = org.organization_profile || org.build_organization_profile

    if org_profile.stripe_customer_id.blank?
      customer = begin
        create_stripe_customer!
      rescue Stripe::InvalidRequestError => err
        errors.add(:base, "Failed to create Stripe account: #{err.message}")
        return false
      end

      org_profile.stripe_customer_id = customer[:id]

      unless org_profile.save
        errors.add(:base, "Could update organization profile: #{org_profile.errors.full_messages.to_sentence}")
        return false
      end

      org_profile.instrument_stripe_customer_create(actor: actor)
    end

    billing_result = Billing::CreateCustomer.perform(
      org,
      details: { omit_billing_info: true },
      purpose: :sponsors,
    )

    unless billing_result.success?
      errors.add(:base, "Could not complete billing account setup: #{billing_result.error_message}")
      return false
    end

    true
  end

  sig { returns(T::Boolean) }
  def call
    return false unless valid?

    org.set_active_sponsors_invoice_migration_lock

    InitializeInvoicedSponsorJob.perform_later(
      org: org,
      name: name,
      email: email,
      address: address.to_h,
      actor: actor
    )

    true
  end

  private

  sig { returns T.nilable(User) }
  attr_reader :actor

  # Private: Cancel any existing recurring sponsorships, since we have to close our their existing
  #          plan subscription.
  sig { returns(T::Boolean) }
  def cancel_existing_sponsorships
    existing_sponsorships = T.unsafe(org.active_sponsorships_as_sponsor_relation).recurring
    return true unless existing_sponsorships.any?

    failed_cancellation_count = 0

    existing_sponsorships.each do |sponsorship|
      result = sponsorship.cancel(actor: User.staff_user, reason: :INVOICED_SPONSOR_CREATED, force: true)

      if result.success
        GitHub.dogstats.increment("#{DATADOG_PREFIX}.sponsorship_cancelled")
      else
        GitHub.dogstats.increment("#{DATADOG_PREFIX}.sponsorship_cancellation_failure")
        failed_cancellation_count += 1
      end
    end

    unless failed_cancellation_count.zero?
      errors.add(:base, "Failed to cancel #{failed_cancellation_count} sponsorships. " \
        "Try manually cancelling any existing sponsorships and then try again")
      return false
    end

    true
  end

  # Private: Close out the org's existing Zuora subscription plan, since we are creating a new one for
  #          their invoiced billing account.
  sig { returns(T::Boolean) }
  def close_zuora_subscription
    return true unless plan_subscription = org.sponsors_plan_subscription

    unless plan_subscription.cancellable?
      errors.add(:base, "Unable to close out existing Sponsors plan subscription")
      return false
    end

    result = ::Billing::CloseZuoraSubscription.perform(
      zuora_subscription_number: plan_subscription.zuora_subscription_number,
      plan_subscription: plan_subscription,
    )

    unless result.success?
      errors.add(:base, "Failed to close out Sponsors plan subscription: #{result}")
      return false
    end

    true
  end

  # Private: Create a Stripe customer with the information provided.
  sig { returns(Stripe::Customer) }
  def create_stripe_customer!
    # See https://stripe.com/docs/api/customers/create
    Stripe::Customer.create(
      name: name,
      address: address.to_h,
      email: email,
      shipping: {
        name: name,
        address: address.to_h,
      },
    )
  end

  sig { void }
  def ensure_sponsors_enabled
    return if GitHub.sponsors_enabled?
    errors.add(:base, "GitHub Sponsors is not an available feature")
  end

  sig { void }
  def ensure_customer_does_not_exist
    return unless org.sponsors_customer.present?
    errors.add(:base, "This organization already has set up an invoiced Sponsors account")
  end

  sig { void }
  def ensure_valid_address
    unless address.valid?
      address.errors.each do |error|
        errors.add("address_#{error.attribute}", error.message)
      end
    end
  end

  class Address
    extend T::Sig
    include ActiveModel::Validations

    validates :line1, :city, presence: true
    validates :country, inclusion: {
      in: ::TradeControls::Countries.currently_unsanctioned.map { |(_, alpha2, _, _)| alpha2 },
      message: "must be a valid country code",
    }
    validates :postal_code, presence: true, if: :postal_code_required?
    validates :state, presence: true, if: :state_required?

    sig do
      params(
        line1: String,
        line2: String,
        city: String,
        state: String,
        postal_code: String,
        country: String,
      ).void
    end
    def initialize(line1:, line2:, city:, state:, postal_code:, country:)
      @line1       = line1
      @line2       = line2
      @city        = city
      @state       = state
      @postal_code = postal_code
      @country     = country
    end

    sig { returns(String) }
    attr_reader :line1, :line2, :city, :state, :postal_code, :country

    sig { returns(AddressHash) }
    def to_h
      {
        line1: line1,
        line2: line2,
        city: city,
        state: state,
        postal_code: postal_code,
        country: country,
      }
    end

    private

    sig { returns(T::Boolean) }
    def state_required?
      country == "US" || country == "CA"
    end

    sig { returns(T::Boolean) }
    def postal_code_required?
      return false unless country.present?
      ::TradeControls::Countries.postal_code_required_geo?(country)
    end
  end
end
