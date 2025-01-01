# typed: strict
# frozen_string_literal: true

# A Customer is a named container for an entity that pays for multiple
# organizations, users, and/or enterprise installs.
class Customer < ApplicationRecord::Domain::Users
  include GitHub::FlipperActor
  include GitHub::Memoizer
  include GitHub::Validations
  include GitHub::VexiActor
  include Configurable
  include Configurable::ResellerCustomer
  include Customer::ContactDependency
  include Customer::CreditCheckDependency
  include Customer::InstrumentationDependency
  include Customer::LicensingDependency
  include Customer::SponsorsDependency
  include Customer::MissingPaymentNotificationDependency
  include Instrumentation::Model

  attribute :name, StringFromBinary.new
  alias_attribute :metered_ghe, :metered_plan

  DEFAULT_PURPOSE = :general

  BILLING_PLATFORM_ACTIONS_ROLLOUT_DATE = T.let(DateTime.new(2023, 8, 1, 17, 30, 0).utc, Time)
  BILLING_PLATFORM_COPILOT_ROLLOUT_DATE = T.let(DateTime.new(2023, 9, 5, 18, 0, 0).utc, Time)
  BILLING_PLATFORM_GA_ROLLOUT_DATE = T.let(DateTime.new(2024, 6, 3, 17, 0, 0).utc, Time)

  BILLING_TYPE_INVOICE = "invoice"
  BILLING_TYPE_CARD = "card"
  BILLING_TYPES = T.let([BILLING_TYPE_INVOICE, BILLING_TYPE_CARD].freeze, T::Array[String])

  COUNTRY_CODES_SUBJECT_TO_SALES_TAX = T.let(%w(US JP), T::Array[String])
  COUNTRY_CODES_REQUIRING_VALIDATED_ADDRESS_FOR_SALES_TAX = T.let(%w(US), T::Array[String])
  COUNTRY_CODES_WITH_TAX_EXEMPTION_CERTIFICATES = T.let(%w(US), T::Array[String])

  AUTO_PAY_DISABLE_REASONS = T.let({
    india_rbi: "Disabled to prevent declines tied to new regulations from the Bank of India.",
    staff_override: "Manual override by Staff to prevent payment collection.",
    trade_controls: "Disabled due to account's SDN status.",
    customer_initiated: "Disabled by the customer themselves.",
    enterprise_purchase: "Disabled to prevent payment collection before enterprise purchase.",
  }.freeze, T::Hash[Symbol, String])

  AUTO_PAY_DISABLE_REASONS_ALLOWED_FOR_ENABLE = T.let(%i(
    customer_initiated
    enterprise_purchase
    trade_controls
  ), T::Array[Symbol])

  MEUSE_REPORT_WINDOW = 180

  # Public: Represents the billing purpose of this customer, like what kind of purchases is the Zuora account intended
  # to be used for.
  enum :purpose, {
    general:  0, # any and all billing
    sponsors: 1, # sponsorships only
  }, suffix: true

  serialize :auto_pay_reasons, type: Set
  serialize :disabled_reasons, type: Set

  after_commit :set_business_billing_trouble_notice, on: [:create, :update]
  after_commit :update_customer_in_billing_platform, on: [:create, :update]
  after_commit :update_customer_in_licensify, on: [:create, :update]
  after_commit :instrument_org_disabled, if: :saved_change_to_locked_at?, on: [:create, :update]
  after_commit :record_plan_change_transaction, if: :saved_change_to_locked_at?
  after_commit :sync_vat_code, if: :saved_change_to_vat_code?, on: [:create, :update]
  after_commit :sync_to_trade_screening_record
  after_update_commit :rescreen_on_pii_update, if: :saved_change_to_vat_code?
  after_update_commit :instrument_metered_via_azure, if: :saved_change_to_metered_via_azure?
  after_update_commit :instrument_azure_subscription_id, if: :saved_change_to_azure_subscription_id?
  after_update_commit :instrument_billed_via_billing_platform, if: :saved_change_to_billed_via_billing_platform?
  after_update_commit :instrument_billing_end_date_updated, if: :saved_change_to_billing_end_date?
  after_update_commit :unlock_billing_for_valid_payment, if: :saved_change_to_azure_subscription_id?

  before_validation :set_metered_via_azure, if: :azure_subscription_id_changed?

  # Public: String full legal name. (Example: Apple, Inc.)
  validates_presence_of :name

  validates :emails, unicode3: true
  validates :billing_extra, unicode3: true
  validates :region, unicode3: true
  validates :postal_code, unicode3: true
  validates :vat_code, unicode3: true
  validates :description, unicode3: true
  validates :bill_cycle_day, inclusion: { in: 0..31,  message: "Bill cycle day should be from 0 - 31" }

  # Public: String universally unique identifier for external systems. Not
  # intended for use as an identifier in this application.
  before_validation :set_external_uuid, on: [:create, :update]
  validates_presence_of :external_uuid

  validates :billing_end_date,
    presence: { if: :invoiced?, message: "must be specified for invoiced customers" },
    datetime_in_supported_range: true

  validates :azure_subscription_id,
    format: { with: /\A[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}\Z/, allow_nil: true }

  validate :metered_via_azure_not_allowed_for_users
  validates :azure_subscription_id, presence: true, if: :metered_via_azure?

  # Public: Optional parent Customer record. (i.e. Yammer's parent might be
  # Microsoft, Inc.)
  belongs_to :parent_customer, class_name: "Customer"

  # Public: A verified email used to contact a human about billing.
  belongs_to :billing_email, class_name: "UserEmail"

  # Public: Optional children Customer records.
  has_many :child_customers, class_name: "Customer", foreign_key: "parent_customer_id", dependent: :destroy # rubocop:todo Rails/InverseOf

  # Public: Association record between a Customer and a User or Organization
  # account. Also holds state and verification status information.
  has_many :customer_accounts, dependent: :destroy

  has_many :plan_subscriptions, class_name: "Billing::PlanSubscription", dependent: :destroy
  has_one :plan_subscription, -> { general_purpose }, class_name: "Billing::PlanSubscription"

  has_one :manual_dunning_period, class_name: "Billing::ManualDunningPeriod", dependent: :destroy

  has_many :subscription_items, through: :plan_subscriptions, class_name: "Billing::SubscriptionItem"
  has_many :active_subscription_items, -> { T.unsafe(self).active }, through: :plan_subscriptions,
    class_name: "Billing::SubscriptionItem"

  # Public: Organization accounts this customer is actively paying for.
  has_many :organizations,
    -> { where(type: "Organization").distinct },
    through: :customer_accounts,
    class_name: "Organization",
    source: :user

  # Public: Enterprise account this customer is actively paying for.
  has_one :business
  has_one :business_including_deleted, -> { Business.including_deleted }, class_name: "Business"

  # Public: User accounts this customer is actively paying for.
  has_many :users,
    -> { where(type: "User").distinct },
    through: :customer_accounts

  # Public: Represents how this customer is paying for GitHub and the payment
  # processor used to collect $$.
  #
  # This User's PaymentMethod which represents how this user is
  # paying for GitHub and the payment processor used to collect $$. A nil
  # payment_method means this user is not paying for GitHub.
  has_one :payment_method, dependent: :destroy

  has_one :sales_serve_plan_subscription, class_name: "Billing::SalesServePlanSubscription", dependent: :destroy

  has_many :billing_transactions, class_name: "Billing::BillingTransaction"

  has_many :pending_plan_changes, class_name: "Billing::PendingPlanChange", dependent: :destroy

  has_many :incomplete_pending_plan_changes, -> { T.unsafe(self).incomplete }, class_name: "Billing::PendingPlanChange"
  has_many :pending_subscription_item_changes,
    class_name: "Billing::PendingSubscriptionItemChange",
    through: :incomplete_pending_plan_changes


  has_many :pending_subscription_item_changes,
    class_name: "Billing::PendingSubscriptionItemChange",
    through: :incomplete_pending_plan_changes

  has_one :billing_platform_enabled_product, dependent: :destroy

  has_one :tax_exemption_status, class_name: "Billing::TaxExemptionStatus", dependent: :destroy

  scope :with_zuora_account_id, ->(zuora_account_id) { where(zuora_account_id: zuora_account_id) }
  scope :billed_in_billing_platform, -> { where(billed_via_billing_platform: true) }
  scope :not_billed_in_billing_platform, -> { where(billed_via_billing_platform: false) }
  scope :in_cohort, ->(cohort_name) {
    joins(:billing_platform_enabled_product)
      .where(billing_platform_enabled_products: { cohort_name: cohort_name })
  }

  delegate :auto_pay?, :credit_balance, to: :zuora_object_account, allow_nil: true

  after_commit :set_was_invoiced, if: :invoiced?

  # Public: Redis key used for tracking an update credit card transaction
  #
  sig { returns(String) }
  def update_payment_method_key
    "user:updating_credit_card:#{id}"
  end

  sig { returns(String) }
  def metered_via_azure_key
    "customer:metered_via_azure:#{id}"
  end

  sig { returns(String) }
  def invalid_azure_subscription_id_key
    "customer:invalid_azure_subscription_id:#{id}"
  end

  sig { returns(String) }
  def was_invoiced_key
    "customer:was_invoiced:#{id}"
  end

  sig { returns(T::Boolean) }
  def set_was_invoiced
    return false unless GitHub.flipper[:was_invoiced_kv].enabled?
    ActiveRecord::Base.connected_to(role: :writing) { Billing::Kv.store.setnx(was_invoiced_key, "true") }
  end

  sig { returns(T::Boolean) }
  def was_invoiced?
    Billing::Kv.store.exists(was_invoiced_key).value { false }
  end

  sig { returns(T.nilable(String)) }
  def enabled_metered_via_azure_at
    Billing::Kv.store.get(metered_via_azure_key).value { nil }
  end

  sig { returns(T::Boolean) }
  def can_disable_metered_via_azure?
    enabled_metered_via_azure_at.nil?
  end

  sig { returns(T::Boolean) }
  def has_auto_pay_enabled?
    auto_pay_reasons.empty?
  end

  sig { returns(T::Boolean) }
  memoize def invalid_azure_subscription_detected?
    return false unless azure_subscription_id.present?
    Billing::Kv.store.exists(invalid_azure_subscription_id_key).value!
  end

  # Public: Retrieve the customer's general-purpose plan subscription based on their payment type.
  sig { returns(T.nilable(T.any(Billing::PlanSubscription, Billing::SalesServePlanSubscription))) }
  def active_plan_subscription
    if invoiced?
      sales_serve_plan_subscription
    else
      plan_subscription
    end
  end

  # The changes that will occur on the users next billing date
  sig { returns(T.nilable(Billing::PendingPlanChange)) }
  def pending_cycle_change
    # TODO: this requires multiple times until pending cycle change is set
    # If we switch this to memoize it may break things so let's do it separately
    @pending_cycle_change ||= pending_plan_changes.incomplete.not_past.first
  end

  # Public: Returns the given users pending_cycle_change
  sig do
    returns(
      T.any(
        Promise[Billing::PendingPlanChange],
        Promise[Promise[T.nilable(Billing::PendingPlanChange)]]
      )
    )
  end
  def async_pending_cycle_change
    return Promise.resolve(@pending_cycle_change) if @pending_cycle_change

    async_pending_plan_changes.then do |pending_changes|
      incomplete_changes = T.unsafe(pending_changes).reject(&:is_complete).sort_by(&:id)

      Promise.all(incomplete_changes.map(&:async_pending_subscription_item_changes)).then do |changes_item_changes|
        if item_change = changes_item_changes.detect(&:any?)&.first
          next_plan_change = item_change.pending_plan_change
          @pending_cycle_change = T.let(next_plan_change, T.nilable(Billing::PendingPlanChange))
        end
      end
    end
  end

  # Public: Update the customer with the payment details.
  #
  # payment_details - A Hash of payment details:
  #                   :charge        - Boolean whether to attempt a recurring charge with this update. Default: true
  #                   :billing_extra - String extra billing information.
  #                   :vat_code      - String VAT Identification Number.
  #                   :paypal_nonce  - String nonce representing a paypal account (optional).
  #                   :credit_card   - A Hash of potentially encrypted CC info, including:
  #                     * :number           - CC number as a String.
  #                     * :expiration_month - Expiration month as a String of form MM
  #                     * :expiration_year  - Expiration year as a String of form YY
  #                     * :cvv              - CVV as a String (e.g. "420")
  #                   :billing_address  - The billing address as a Hash of optionally encrypted CC info
  #                     * :country_code_alpha3 - Country as a String
  #                     * :region              - Region as a String
  #                     * :postal_code         - Postal code as a String
  #
  # TODO: Would be nice if payment details was a struct
  sig { params(payment_details: T::Hash[Symbol, T.untyped]).returns(GitHub::Billing::Result) }
  def update_payment_method_details(payment_details)
    self.vat_code = payment_details[:vat_code] if payment_details.has_key?(:vat_code)
    self.billing_extra = payment_details[:billing_extra] if payment_details.has_key?(:billing_extra)

    billing_address = payment_details[:billing_address] || {}

    self.country_code_alpha2 = Customer.countries[billing_address[:country_code_alpha3]]
    self.region              = billing_address[:region]
    self.postal_code         = billing_address[:postal_code]

    payment_method = T.must(self.payment_method)

    if payment_method.using_braintree_processor? && zuora_account_id.present?
      payment_method.update(
        payment_processor_customer_id: zuora_account_id,
        payment_processor_type: PaymentMethod.zuora_processor_slug,
      )
    end
    result = payment_method.update_payment_details(payment_details)

    if payment_method.blocklisted? && payment_method.user.present?
      payment_method_user = T.must(payment_method.user)
      blocklisted_payment_method = BlacklistedPaymentMethod.create_from_user_and_payment_method(payment_method_user, payment_method) # rubocop:disable Naming/InclusiveLanguage
      blocklisted_payment_method.execute_consequence
    end

    save if result.success?
    result
  end

  # TODO: this method should be removed once we move towards the new Contact table
  # this and the attributes here should be moved to the Contact table
  # billing_contact - this should only be passed in when the contact was updated to avoid the need of performing an unnecessary
  #  lookup in the database or updating customer with old data
  sig { params(billing_contact: Billing::Contact).returns(T::Boolean) }
  def update_contact_information(billing_contact: self.billing_contact)
    return false unless billing_contact.billing?
    update(
      name: billing_contact.fullname,
      street_address: billing_contact.address1,
      postal_code: billing_contact.postal_code,
      country_code_alpha2: billing_contact.country_code,
      region: billing_contact.region,
      vat_code: billing_contact.vat_code,
    )

    return true unless zuora_account_id = self.zuora_account_id

    UpdateZuoraAccountInformationJob.perform_later(zuora_account_id: zuora_account_id, contact_id: billing_contact.id)

    # We only want to update the linked orgs if this contact is being updated. If we're only updating zuora information
    # due to linking a a contact to an org, the contact information itself hasn't changed so we don't need to update all the linked orgs.
    return true unless linked_customer_id = billing_contact.customer&.id
    update_linked_orgs_contact_information(billing_contact:) if linked_customer_id == id
    true
  end

  sig { returns(T::Boolean) }
  def update_payment_contact
    return false unless payment_method.present?
    Billing::SynchronizeCustomerPaymentContactJob.perform_later(self)
    true
  end

  # Public: Updates the address information in Zuora, skipping the more complex route
  # of updating all payment details.
  sig { params(payment_details: Billing::PaymentProcessorPaymentDetails).returns(GitHub::Billing::Result) }
  def update_payment_contact!(payment_details)
    GitHub::Billing::Result.from_zuora(T.must(payment_method).payment_processor.update_customer_contact(payment_details: payment_details))
  end

  # Public: Boolean does this customer have a record in Zuora? Customers
  # that keep credit card or other self serve payment information like PayPal on
  # file will have records in Zuora.
  sig { returns(T::Boolean) }
  def zuora?
    zuora_account_id.present?
  end

  # Public: String comma separated email addresses to send invoices to.
  # :emails

  # Public: Array of string email addresses.
  sig { returns(T::Array[String]) }
  def email_addresses
    emails.to_s.split(",")
  end

  # Public: Set the emails attributes with an array of email addresses or a
  # comma separated string of emails.
  sig { params(emails: T.any(T::Array[String], String)).void }
  def email_addresses=(emails)
    self[:emails] = if emails.is_a?(Array)
      emails.join(",")
    else
      emails
    end
  end

  # Public: String extra billing information to appear on every receipt.
  # :billing_extra

  # Public: Billing address attributes.
  # :street_address
  # :country_code_alpha2
  # :region
  # :postal_code
  # :vat_code

  sig { returns(String) }
  def to_param
    "#{id}-#{name.parameterize}"
  end

  # Public: Gets the Zuora Account object from the Zuora API
  #
  sig { returns(T.nilable(Zuorest::Model::Account)) }
  def zuora_account
    return unless zuora?
    Zuorest::Model::Account.find(self.zuora_account_id)
  end

  # Public: checks if this account has an external account
  sig { returns(T::Boolean) }
  def external_account?
    zuora?
  end

  # Updates the external account name in Zuora
  # - A successful response from the update action looks like [{"Id" => "id...", "Success" => true}]
  # - But it could also be a 500 if the account is not found
  # - or nil if there's no external_account?
  sig do
    returns(
      T.any(
        T.nilable(T::Array[T::Hash[String, T.any(String, T::Boolean)]]),
        T.noreturn
      )
    )
  end
  def update_external_account_name
    return unless external_account?

    account = customer_accounts.first
    zuora = T.must(zuora_account)
    business = self.business
    name = business ? business.name : account&.user&.login

    zuora.update!(Name: name)
    account_response = GitHub.zuorest_client.get_account(zuora.id)
    new_name_params = { FirstName: name, LastName: name }
    GitHub.dogstats.time("zuora.timing.action_contact_update") do
      GitHub.zuorest_client.update_action({
        objects: [
          { Id: account_response["SoldToId"] }.merge!(new_name_params),
          { Id: account_response["BillToId"] }.merge!(new_name_params),
        ],
        type: "Contact",
      })
    end
  end

  # Public: Cancel all external subscriptions related to the customer
  #
  # Use Billing::CloseZuoraSubscription instead if you need to verify the result.
  #
  sig { void }
  def cancel_external_subscriptions
    plan_subscriptions.select(&:has_external_subscription?).each do |plan_sub|
      plan_sub.cancel_external_subscription
    end

    nil
  end

  # Maps Alpha3(3 letter code) Country to Alpha2(2 letter code).
  #
  @@countries = T.let(nil, T.nilable(T::Hash[String, String]))
  sig { returns(T::Hash[String, String]) }
  def self.countries
    @@countries ||= ::Braintree::Address::CountryNames.inject({}) do |memo, c|
      memo[c[2]] = c[1]
      memo
    end
  end

  # Public: Returns whether or not this customer's billing is handled via invoicing. Returns false
  # if the customer's billing is handled via a self-serve payment method or if the customer's
  # billing_type is unset.
  sig { returns(T::Boolean) }
  def invoiced?
    billing_type == BILLING_TYPE_INVOICE
  end

  # Public: Returns whether or not this customer's billing is handled via a self-serve payment
  # method. Returns false if the customer's billing is handled via invoicing or if the customer's
  # billing_type is unset.
  sig { returns(T::Boolean) }
  def self_serve_payment?
    billing_type == BILLING_TYPE_CARD
  end

  # Public: Updates attributes from Zuora into the Customer object
  sig { void }
  def update_from_zuora
    return unless account = zuora_object_account

    update(bill_cycle_day: account.bill_cycle_day)
  end

  # Public: Setter for Azure Subscription ID that converts blanks to `nil` to avoid
  #         unique index constraint violations when there are multiple records saved with
  #         blank values
  sig { params(value: T.nilable(String)).returns(T.nilable(String)) }
  def azure_subscription_id=(value)
    super(value.presence)
  end

  sig { returns(T::Boolean) }
  def zuora_account_active?
    account = zuora_object_account
    !account.nil? && account.active?
  end

  # Public: Name and address of the contact whose billing information is used for the zuora account
  #
  # Required keys include FirstName, LastName
  # Possible keys include Address1, Address2, City, State, PostalCode, and Country
  # https://www.zuora.com/developer/api-reference/#operation/Object_GETContact
  #
  sig { returns(Sponsors::BillingContactResult) }
  def zuora_billing_contact
    return T.must(@zuora_billing_contact) if defined?(@zuora_billing_contact)

    @zuora_billing_contact = T.let(
      if account = zuora_object_account
        account.billing_contact
      else
        Sponsors::BillingContactResult.error("No Zuora Account")
      end,
      T.nilable(Sponsors::BillingContactResult)
    )

    T.must(@zuora_billing_contact)
  end

  sig { returns(T::Boolean) }
  def requires_manual_transactions?
    !!payment_method&.from_india?
  end

  sig { returns(T::Boolean) }
  def requires_invoice_by_email?
    !!payment_method&.from_japan?
  end

  sig { returns(T::Boolean) }
  memoize def requires_sales_tax_workaround_for_updates?
    return false unless billable_owner&.feature_enabled?(:billing_sales_tax_workaround_for_subscription_updates)
    in_taxable_country?
  end

  sig { returns(T::Boolean) }
  def has_valid_address_for_tax?
    return true unless requires_valid_address_for_tax?
    return contact_for_tax.address_validated_at.present? if contact_for_tax.persisted?
    return true if billable_owner&.billing_contact&.address_validated_at.present?
    false
  end

  sig { returns(T::Boolean) }
  def requires_valid_address_for_tax?
    COUNTRY_CODES_REQUIRING_VALIDATED_ADDRESS_FOR_SALES_TAX.include?(country_code_for_tax_purposes)
  end

  sig { returns(T::Boolean) }
  def in_taxable_country?
    COUNTRY_CODES_SUBJECT_TO_SALES_TAX.include?(country_code_for_tax_purposes)
  end

  sig { returns(T::Boolean) }
  def in_taxable_country_with_exemptions?
    return false unless in_taxable_country?
    COUNTRY_CODES_WITH_TAX_EXEMPTION_CERTIFICATES.include?(country_code_for_tax_purposes)
  end

  sig { returns(String) }
  def country_code_for_tax_purposes
    country_code = contact_for_tax.country_code || billable_owner&.billing_contact&.country_code
    return country_code if country_code.present?

    # When no billing information is present, it's possible for the customer to have billing information saved in Zuora.
    # We detect this scenario based on whether or not the customer has a valid payment payment.
    return "" unless payment_method&.valid_payment_token?

    # Zuora doesn't provide the country name in a way that is easily mappable to a country code.
    # So we're forced to hardcode the country codes for the countries we care about.
    country = zuora_sold_to_country
    case country
    when "United States"
      "US"
    when "Japan"
      "JP"
    else
      ""
    end
  end

  sig { returns(Billing::Contact) }
  def contact_for_tax
    shipping_contact = self.shipping_contact if self.shipping_contact.persisted?
    shipping_contact || billing_contact
  end

  sig { params(reason: T.nilable(Billing::Public::BillingDisabledReasons), send_email: T::Boolean).void }
  def lock_billing(reason: nil, send_email: false)
    if reason
      update!(locked_at: GitHub::Billing.now, disabled_reasons: disabled_reasons.add(reason.serialize))
    else
      update!(locked_at: GitHub::Billing.now)
    end
    track_lock_billing(reason: reason)
  end

  sig { returns(T::Boolean) }
  def billing_locked?
    locked_at.present?
  end

  sig { void }
  def unlock_billing
    previously_locked_at = locked_at
    previously_disabled_reasons = disabled_reasons
    update!(locked_at: nil, disabled_reasons: Set.new)
    track_unlock_billing(previously_locked_at:, previously_disabled_reasons:)
  end

  # Users affected by India RBI regulations cannot use auto-pay or make manual payments via PayPal
  sig { returns(T::Boolean) }
  def autopay_disabled_by_india_rbi?
    !!auto_pay_reasons.include?(:india_rbi)
  end

  sig { returns(T::Boolean) }
  def autopay_disabled_by_trade_controls?
    !!auto_pay_reasons.include?(:trade_controls)
  end

  sig { returns(T::Boolean) }
  def remove_disabled_by_authorization_failure_reason
    return false unless billing_disabled_by_authorization_failure?
    update(disabled_reasons: disabled_reasons.delete(Billing::Public::BillingDisabledReasons::AuthorizationFailure.serialize))
  end

  sig { params(reason: Billing::Public::BillingDisabledReasons).returns(T::Boolean) }
  def remove_disabled_reason(reason)
    update(disabled_reasons: disabled_reasons.delete(reason.serialize))
  end

  sig { params(reason: Billing::Public::BillingDisabledReasons).returns(T::Boolean) }
  def update_disabled_reasons(reason)
    update(disabled_reasons: disabled_reasons.add(reason.serialize))
  end

  sig { returns(T::Boolean) }
  def billing_disabled_by_authorization_failure?
    !!disabled_reasons.include?(Billing::Public::BillingDisabledReasons::AuthorizationFailure.serialize)
  end

  sig { returns(T::Boolean) }
  def billing_disabled_by_blocklisted_payment_method?
    !!disabled_reasons.include?(Billing::Public::BillingDisabledReasons::BlocklistedPaymentMethod.serialize)
  end

  sig { returns(T::Boolean) }
  def billing_disabled_by_missing_payment_method?
    !!disabled_reasons.include?(Billing::Public::BillingDisabledReasons::MissingPaymentMethod.serialize)
  end

  sig { returns(T::Boolean) }
  def remove_disabled_by_missing_payment_method_reason
    return false unless billing_disabled_by_missing_payment_method?
    remove_disabled_reason(Billing::Public::BillingDisabledReasons::MissingPaymentMethod)
  end

  # Public: Compares a customer's credit balance to a given payment amount.
  #
  # payment_amount - Billing::Money
  sig { params(payment_amount: Billing::Money).returns(T::Boolean) }
  def sufficient_balance?(payment_amount)
    credit_balance >= payment_amount
  end

  # Public: Gets the Zuora Account object from the Zuora Object API
  #
  # This includes more fields than the non-object API, which is used in Customer#zuora_account
  #
  sig { returns(T.nilable(::Billing::Zuora::Account)) }
  def zuora_object_account
    return @zuora_object_account if defined?(@zuora_object_account)

    @zuora_object_account = T.let(::Billing::Zuora::Account.find(zuora_account_id), T.nilable(::Billing::Zuora::Account))
  end

  # Public: Attempts to grab the billable owner for a customer.
  #
  # The billable owner for a customer if a business is present should
  # be the business. Otherwise, if the customer has associated users
  # or orgs, we want to verify that only one is present and return that
  # user/orgs billable owner.
  #
  # If there is more than one present, it might be hard to determine
  # the billable owner as there are cases of orgs belonging to an
  # enterprise that is different than the user/orgs billable owner.
  # In these cases, we return nil here.
  sig { returns(T.nilable(T.any(User, Business))) }
  def billable_owner
    return business if business.present?
    return organizations.first&.billable_owner if organizations.present? && organizations.one?
    users.first!.billable_owner if users.present? && users.one?
  end

  sig { returns(String) }
  def purpose_description
    return "Sponsors-specific" if sponsors_purpose?
    return "general-purpose" if general_purpose?
    "unknown"
  end

  sig { returns(T::Boolean) }
  def requires_azure_subscription?
    has_active_enterprise_agreement? || metered_via_azure?
  end

  sig { returns(T::Boolean) }
  def has_active_enterprise_agreement?
    owner = billable_owner
    owner.is_a?(Business) && owner.enterprise_agreements.active.any?
  end

  sig { returns(T::Boolean) }
  def has_active_vss_enterprise_agreement?
    owner = billable_owner
    owner.is_a?(Business) && owner.enterprise_agreements.visual_studio_bundle.active.any?
  end

  sig { returns(T.nilable(String)) }
  def discount_plan_name
    billable_owner&.plan&.entitlement_plan_name
  end

  sig { params(previous_customer_id: T.nilable(String), async: T::Boolean, unbundle_ghas: T.nilable(T::Boolean)).void }
  def onboard_to_all_billing_platform_products(previous_customer_id: nil, async: true, unbundle_ghas: nil)
    if GitHub.flipper[:billing_check_if_org_upgraded_to_business_before_onboarding].enabled?
      return if should_skip_onboard_to_billing_platform?
    end

    update!(billed_via_billing_platform: true)

    if async
      Billing::OnboardCustomerToProductInBillingPlatformJob.perform_later(
        customer_id: self.id,
        products: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum.serialized_enums,
        previous_customer_id: previous_customer_id,
        unbundle_ghas: unbundle_ghas
      )
    else
      Billing::OnboardCustomerToProductInBillingPlatformJob.perform_now(
        customer_id: self.id,
        products: Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum.serialized_enums,
        previous_customer_id:
        previous_customer_id,
        unbundle_ghas: unbundle_ghas
      )
    end
  end

  sig { void }
  def set_metered_plan_and_onboard_to_all_billing_platform_products
    if self.billable_owner&.is_a?(Business)
      # Set businesses only to use a metered plan
      update!(metered_plan: true)
    end

    onboard_to_all_billing_platform_products
  end

  sig { returns(T::Boolean) }
  def should_skip_onboard_to_billing_platform?
    # Checks to see if this customer belongs to an enterprise
    if organizations.first&.delegate_billing_to_business?
      GitHub.dogstats.increment("billing_platform.skip_onboarding_org_delegate_billing_to_business")
      log_context = {
        "gh.billing.billable_entity.id" => self.billable_owner&.id,
        "gh.billing.customer.id" => self.id,
      }
      GitHub.logger.info("Skipping onboard of org that is owned by a business", log_context)
      billing_platform_enabled_product = BillingPlatformEnabledProduct.find_or_create_by!(customer_id: self.id)
      billing_platform_enabled_product.cohort_name = "delegated-to-enterprise"
      billing_platform_enabled_product.planned_migration_date = DateTime.strptime("01/15/2099", "%m/%d/%Y")
      billing_platform_enabled_product.save
      return true
    end
    false
  end

  # vNext native indicates the customer has only ever had access to billing through vNext.
  # Meuse was never a billing option for this customer.
  sig { returns(T::Boolean) }
  def is_vnext_native?
    org = organizations.first
    user_customer = users.present? && users.one?
    entity_present = org.present? || business.present? || user_customer
    # is a business, org, or user customer
    return false unless entity_present
    # is billed via billing platform
    return false unless billed_via_billing_platform?
    # is created after the billing platform GA rollout date
    return false unless created_at >= BILLING_PLATFORM_GA_ROLLOUT_DATE
    # is migrated to vNext within 1 day of creation
    return false if vnext_migration_date.present? && T.must(vnext_migration_date) > created_at + 1.day

    true
  end

  # Public: planned migration date that will be used for pre migration purposes like sending emails and displaying welcome banner
  #
  # Returns Date
  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def vnext_planned_migration_date
    self.billing_platform_enabled_product&.planned_migration_date
  end

  # Public: actual migration date of when a customer is migrated to vNext
  #
  # Returns Date
  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def vnext_migration_date
    self.billing_platform_enabled_product&.migration_date
  end

  # Public: planned migration date of when a customer is migrated to vNext
  #
  # Returns String
  sig { returns(T.nilable(String)) }
  def readable_vnext_planned_migration_date
    vnext_planned_migration_date&.utc.strftime("%B %d, %Y %Z")
  end

  # Public: actual migration date of when a customer is migrated to vNext
  #
  # Returns String
  sig { returns(T.nilable(String)) }
  def readable_vnext_migration_date
    vnext_migration_date&.utc.strftime("%B %d, %Y %Z")
  end

  sig { returns(T.nilable(Integer)) }
  def days_since_vnext_migration
    return unless vnext_migration_date

    (DateTime.now.utc.to_date - vnext_migration_date&.to_date).to_i
  end

  sig { returns(T::Boolean) }
  def migration_happened_in_last_thirty_days?
    days_since_migration = days_since_vnext_migration
    return false if days_since_migration.nil?
    days_since_migration <= 30 && days_since_migration >= 0
  end

  sig { returns(T::Boolean) }
  def migration_happened_more_than_thirty_days_ago?
    days_since_migration = days_since_vnext_migration
    return false if days_since_migration.nil?
    days_since_migration > 30
  end

  sig { returns(T::Boolean) }
  def show_migration_banner?
    return false if is_vnext_native?
    return false if billed_via_billing_platform?
    return false unless vnext_planned_migration_date

    planned_migration_date = vnext_planned_migration_date&.utc.to_date
    thirty_days_from_planned_migration = planned_migration_date - 30.days
    date_now = DateTime.now.utc.to_date
    (thirty_days_from_planned_migration..planned_migration_date).include?(date_now)
  end

  sig { returns(T::Boolean) }
  def show_post_migration_banner?
    return false if is_vnext_native?
    return true if migration_happened_in_last_thirty_days?

    false
  end

  sig { returns(Integer) }
  memoize def billing_platform_billing_target
    requires_azure_subscription? ? BillingPlatform::Api::V1::BillingTarget::Azure : BillingPlatform::Api::V1::BillingTarget::Zuora
  end

  sig { returns(T::Array[String]) }
  def products_billed_via_billing_platform
    enabled_products = []

    bp_enabled_products = self.billing_platform_enabled_product || build_billing_platform_enabled_product
    enabled_products = bp_enabled_products.all_enabled_products
    enabled_products
  end

  # Used to display enabled products in user facing UI
  sig { params(with_models: T::Boolean).returns(T::Array[String]) }
  def products_billed_via_billing_platform_friendly_names(with_models: true)
    enabled_products = []

    bp_enabled_products = self.billing_platform_enabled_product || build_billing_platform_enabled_product
    enabled_products = bp_enabled_products.all_enabled_products_friendly_names(with_models:)
    enabled_products
  end

  sig { returns(T::Boolean) }
  def packages_billed_on_billing_platform?
    !!billing_platform_enabled_product&.packages?
  end

  sig { returns(T::Boolean) }
  def copilot_billed_on_billing_platform?
    return false if BILLING_PLATFORM_COPILOT_ROLLOUT_DATE > Time.now.utc
    !!billing_platform_enabled_product&.copilot
  end

  sig { returns(T::Boolean) }
  def git_lfs_billed_on_billing_platform?
    !!billing_platform_enabled_product&.git_lfs?
  end

  sig { returns(T::Boolean) }
  def valid_zuora_with_payment?
    zuora_with_payment = zuora? &&
      active_plan_subscription&.zuora_subscription_number.present? &&
      (invoiced? || payment_method&.valid_payment_token?)
    !!zuora_with_payment
  end

  sig { returns(T::Boolean) }
  def is_legacy_report_an_option?
    return false if self.is_vnext_native?
    migration_date = self.vnext_migration_date
    return false if migration_date.blank?
    days_since_migration = ((Time.now - migration_date.to_time).to_i / 1.day)
    return true if !self.is_vnext_native? && days_since_migration < MEUSE_REPORT_WINDOW

    false
  end

  sig { returns(T::Boolean) }
  def valid_metered_azure_payment_method?
    metered_ghe? && requires_azure_subscription? && azure_subscription_id.present?
  end

  sig { void }
  def onboard_copilot_premium_request_zero_dollar_budget
    onboard_zero_dollar_budget(pricing_target_type: "SkuPricing", pricing_target_id: "copilot_premium_request")
  end

  sig { void }
  def onboard_models_zero_dollar_budget
    onboard_zero_dollar_budget(pricing_target_type: "ProductPricing", pricing_target_id: "models")
  end

  sig { params(pricing_target_type: String, pricing_target_id: String).void }
  def onboard_zero_dollar_budget(pricing_target_type:, pricing_target_id:)
    alert_recipients = billable_owner&.admins&.map(&:global_relay_id) || []
    alert_enabled = alert_recipients == [] ? false : true

    raw_budget_request = {
      targetAmount: 0,
      targetType: "CustomerResource",
      targetId: id.to_s,
      pricingTargetType: pricing_target_type,
      pricingTargetId: pricing_target_id,
      budgetLimitType: "PreventFurtherUsage",
      alertEnabled: alert_enabled,
      alertRecipientUserIds: alert_recipients,
    }

    budget_request = Billing::Platform::Api::UpsertBudgetRequest.new(
      raw_upsert_budget_request: raw_budget_request,
      current_user: User.ghost,
      customer_id: id.to_s,
      this_entity: billable_owner,
    )

    budget_response = billing_platform_client.get_budget(key: budget_request.json_key)

    if !budget_response.is_a?(Billing::Platform::Api::Error) && budget_response[:budget].present?
      log_context = {
        "code.namespace" => self.class.name,
        "code.function" => __method__,
        "gh.billing.billable_entity.id" => billable_owner&.id,
        "gh.billing.billable_entity.login" => billable_owner&.display_login,
        "gh.billing.billable_entity.type" => billable_owner.class.name,
        "gh.billing.customer.id" => self.id,
      }

      GitHub.logger.info("Budget already exists for", log_context)

      datadog_identifier = "billing.onboard_#{pricing_target_id}_zero_dollar_budget.done"

      GitHub.dogstats.increment(
        datadog_identifier,
        tags: ["success:false", "error:budget_already_exists"]
      )
      return
    end

    dogstats_tags = ["success:true"]
    response = billing_platform_client.create_or_update_budget(budget: budget_request.to_json)
    if response.is_a?(Billing::Platform::Api::Error)
      dogstats_tags = ["success:false", "error:#{response.class.name}"]
    end

    GitHub.instrument "billing.budget_create", {
      actor: User.ghost,
      customer_id: id.to_s,
      business: billable_owner,
      target_amount: budget_request.target_amount,
      target_type: budget_request.target_type,
      target_id: budget_request.target_id,
      alert_enabled: budget_request.alert_enabled?,
      pricing_target_type: budget_request.pricing_target_type,
      pricing_target_id: budget_request.pricing_target_id,
      budget_limit_type: budget_request.budget_limit_type,
      alert_recipient_user_ids: budget_request.alert_recipient_user_ids,
      automatic_migration_from_meuse: true,
      status: "success"
    }

    GitHub.dogstats.increment(
      datadog_identifier,
      tags: dogstats_tags
    )
  end

  sig { void }
  def sync_vat_code
    return unless zuora_account_id.present?
    SyncVatCodeJob.perform_later(zuora_account_id: zuora_account_id, vat_code: vat_code)
  end

  private

  # Returns the country for the sold to contact in Zuora.
  # This is intended to only be used if we are missing billing information in dotcom.
  sig { returns(String) }
  def zuora_sold_to_country
    return "" unless GitHub.flipper[:billing_use_zuora_sold_to_country].enabled?

    country = Billing::Kv.store.get(zuora_sold_to_country_key).value { nil }
    if country.present?
      GitHub.dogstats.increment("customer.zuora_sold_to_country", tags: ["success:true", "country:#{country}", "cache_hit:true"])
      return country
    end

    log_context = {
      "code.namespace" => self.class.name,
      "code.function" => __method__,
      "gh.billing.billable_entity.id" => billable_owner&.id,
      "gh.billing.billable_entity.login" => billable_owner&.display_login,
      "gh.billing.billable_entity.type" => billable_owner.class.name,
      "gh.billing.customer.id" => self.id,
      "gh.billing.zuora.account.id" => zuora_account_id,
    }

    zuora = zuora_account
    unless zuora
      GitHub.dogstats.increment("customer.zuora_sold_to_country", tags: ["success:false", "error:zuora_account_not_found"])
      GitHub.logger.error("Zuora account not found", log_context)
      return ""
    end

    sold_to_contact = zuora["soldToContact"]
    unless sold_to_contact
      GitHub.dogstats.increment("customer.zuora_sold_to_country", tags: ["success:false", "error:sold_to_contact_not_found"])
      GitHub.logger.error("Sold to contact not found", log_context)
      return ""
    end

    country = sold_to_contact["country"]
    unless country
      GitHub.dogstats.increment("customer.zuora_sold_to_country", tags: ["success:false", "error:country_not_found"])
      GitHub.logger.error("Country not found", log_context)
      return ""
    end

    ActiveRecord::Base.connected_to(role: :writing) do
      Billing::Kv.store.set(zuora_sold_to_country_key, country)
    end

    GitHub.dogstats.increment("customer.zuora_sold_to_country", tags: ["success:true", "country:#{country}", "cache_hit:false"])
    GitHub.logger.info(log_context)

    country
  rescue Zuorest::HttpError => error
    # This method may be used in UI code paths and getting the country correct is not critical,
    # so we don't want to raise an exception for intermittent Zuora errors.
    GitHub.dogstats.increment("customer.zuora_sold_to_country", tags: ["success:false", "error:#{error.class.name}"])
    GitHub.logger.error(error, log_context)
    ""
  end

  sig { returns(String) }
  def zuora_sold_to_country_key
    "zuora_sold_to_country_#{self.id}"
  end

  sig { void }
  def set_metered_via_azure
    unless azure_subscription_id.present?
      self.metered_via_azure = false
    end
  end

  sig { void }
  def metered_via_azure_not_allowed_for_users
    if metered_via_azure? && users.any?
      errors.add(:metered_via_azure, "cannot be true for customers associated with users")
    end
  end

  sig { returns(T.nilable(String)) }
  def masked_azure_subscription_id
    # Previous Azure subscription is used for unlinking cases, when the Azure subscription id is no longer present.
    azure_subscription_is_or_was = azure_subscription_id || azure_subscription_id_previously_was
    return unless azure_subscription_is_or_was.present?
    range = T.let(5...30, T::Range[Integer])
    # Example: "00000*************************000000"
    azure_subscription_is_or_was.dup.tap { |p| p[range] = "*" * range.size.to_i }
  end

  sig { returns(Symbol) }
  def event_prefix
    :billing_customer
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    payload = {
      azure_subscription_id: masked_azure_subscription_id,
      billing_type: billing_type || "none",
      billed_via_billing_platform: billed_via_billing_platform,
      business: business,
      customer: self,
      linked_azure_subscription: azure_subscription_id.present?,
      metered_ghe: metered_plan,
      metered_via_azure: metered_via_azure?,
      org: organizations.first, # Most customers are associated with a single organization. This helps audit log queries.
      zuora_account_id: zuora_account_id,
      zuora_account_number: zuora_account_number,
    }
    payload[:org_ids] = organization_ids.join(",") if organization_ids.any? && organization_ids.size > 1
    payload.compact
  end

  sig { returns(T::Array[String]) }
  def dogstats_tags
    [
      "billable_owner_type:#{billable_owner.class.name}",
      "billing_type:#{billing_type || "none"}",
      "linked_azure_subscription:#{azure_subscription_id.present?}",
      "metered_ghe:#{metered_plan}",
      "metered_via_azure:#{metered_via_azure?}",
      "billed_via_billing_platform:#{billed_via_billing_platform}"
    ]
  end

  # Private: Sets a uuid for external systems to reference when the Customer
  # record is first created.
  sig { void }
  def set_external_uuid
    self.external_uuid = SecureRandom.uuid if self.external_uuid.blank?
  end

  sig { void }
  def set_business_billing_trouble_notice
    business = self.business
    return unless business.present?
    return unless business.billing_trouble?

    Billing::BusinessBillingTroubleCheckJob.perform_later(business)
  end

  sig { void }
  def instrument_org_disabled
    return unless self.feature_enabled?(:use_billing_locked_rather_than_disabled)
    return unless billable_owner&.organization?
    T.cast(T.must(billable_owner), Organization).set_disabled_org_billing_notice
  end

  sig { void }
  def record_plan_change_transaction
    return unless self.feature_enabled?(:use_billing_locked_rather_than_disabled)
    return if billable_owner.nil?
    return if billable_owner&.business?

    T.cast(T.must(billable_owner), User).record_plan_change_transaction
  end

  sig { void }
  def instrument_metered_via_azure
    if metered_via_azure?
      instrument :metered_via_azure_enabled
    else
      instrument :metered_via_azure_disabled
    end

    GitHub.dogstats.increment("billing_customer.metered_via_azure_change", tags: dogstats_tags)
  end

  sig { void }
  def instrument_azure_subscription_id
    if azure_subscription_id.present?
      instrument :azure_subscription_linked
    else
      instrument :azure_subscription_unlinked
    end

    GitHub.dogstats.increment("billing_customer.azure_subscription_change", tags: dogstats_tags)
  end

  sig { void }
  def instrument_billed_via_billing_platform
    if billed_via_billing_platform?
      instrument :billing_platform_emission_enabled
    else
      instrument :billing_platform_emission_disabled
    end

    GitHub.dogstats.increment("billing_customer.billed_via_billing_platform", tags: dogstats_tags)
  end

  sig { void }
  def instrument_billing_end_date_updated
    billing_end_date_changes = previous_changes[:billing_end_date]
    instrument :billing_end_date_updated, { old_billing_end_date: billing_end_date_changes.first, billing_end_date: billing_end_date_changes.last }
  end

  sig { void }
  def update_customer_in_billing_platform
    return unless GitHub.billing_enabled?

    GitHub.dogstats.increment("billing_customer.billing_platform_update_customer")
    Billing::UpdateCustomerInBillingPlatformJob.perform_later(self)
    GitHub.dogstats.increment("billing_customer.billing_platform_update_customer_called")
  end

  sig { void }
  def update_customer_in_licensify
    return unless GitHub.billing_enabled?
    return unless transaction_include_any_action?([:create]) || saved_change_to_metered_plan?

    UpdateCustomerInLicensifyJob.perform_later(self.id)
  end

  sig { params(billing_contact: Billing::Contact).void }
  def update_linked_orgs_contact_information(billing_contact:)
    return unless billable_owner = self.billable_owner
    return unless billable_owner.is_a?(User)
    return unless billable_owner.persisted?

    # Prevent memoization issues from fetching linked orgs. Tests surfaced this issue
    # when initially creating the contact which would load the orgs and memoize them
    # any further actions on the record would not reload the memoized cache causing the tests to fail
    # due to the orgs not showing up on the instance of the contact.
    owner = User.find(billable_owner.id)
    owner.orgs_linked_to_billing_contact.each { |org| org.customer&.update_contact_information(billing_contact:) }
  end

  sig { returns(T::Boolean) }
  def saved_change_to_locked_at?
    return false unless has_attribute?(:locked_at)
    super
  end

  sig { void }
  def unlock_billing_for_valid_payment
    return unless azure_subscription_id.present?
    return unless azure_subscription_id_previously_was.nil?
    return unless owner = billable_owner
    return unless owner.feature_enabled?(:billing_cpwu_account_downgrade)

    remove_disabled_by_missing_payment_method_reason
    # Use this as there might be other scenarios where we want to keep billing locked
    owner.enable_or_disable!

    # instrument
    analytics_label = {
      ref_business_id: business&.id,
      ref_billing_target: "azure",
      ref_disabled: owner.disabled?,
      ref_days_since: self.days_since_missing_payment_initial_notification
    }.compact.map { |k, v| "#{k}:#{v}" }.join(";")

    GlobalInstrumenter.instrument("analytics.event", {
      category: "missing_payment",
      action: "payment_added",
      label: analytics_label,
      actor: User.find_by(id: GitHub.context[:actor_id]),
    })
  end

  sig { returns(::Billing::Platform::Api::Client) }
  def billing_platform_client
    ::Billing::Platform::Api::Client.new
  end
end
