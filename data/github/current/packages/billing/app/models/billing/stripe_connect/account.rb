# typed: strict
# frozen_string_literal: true

class Billing::StripeConnect::Account < ApplicationRecord::Domain::Billing
  extend T::Sig

  include GitHub::Memoizer
  include Instrumentation::Model
  include Billing::StripeConnect::Account::HydroDependency

  UnavailableBalanceError = Class.new(StandardError)
  class SyncError < StandardError; end

  class PayoutStatus < T::Enum
    enums do
      Pending = new("pending")
      Paid = new("paid")
      Failed = new("failed")
      Canceled = new("canceled")
    end
  end

  self.table_name = "stripe_connect_accounts"

  STRIPE_CONNECT_URL = "https://connect.stripe.com"

  # How many active and inactive accounts one Sponsors listing can have; meant as an
  # abuse-prevention mechanism.
  MAX_ACCOUNTS_PER_SPONSORS_LISTING = 10

  # The business types used by the Stripe Connect API.
  # See https://stripe.com/docs/api/accounts/object#account_object-business_type
  BUSINESS_TYPE_COMPANY = "company"
  BUSINESS_TYPE_INDIVIDUAL = "individual"

  # The interval types and anchor used by the Stripe Connect API.
  # See https://stripe.com/docs/api/accounts/create#create_account-settings-payouts
  PAYOUT_INTERVAL_MONTHLY = "monthly"
  PAYOUT_INTERVAL_MANUAL = "manual"
  # The day of the month when Stripe payouts happen on a "monthly" interval.
  PAYOUT_MONTHLY_ANCHOR = 22
  # Certain countries have restrictions on payout schedules.
  # https://stripe.com/docs/payouts#payout-schedule
  # https://github.com/github/sponsors/issues/4231
  COUNTRIES_WITHOUT_MONTHLY_PAYOUT_SUPPORT = T.let(%w[BR IN].freeze, T::Array[String])

  # The type of Stripe Connect account used by Sponsors.
  # See https://stripe.com/docs/api/accounts/create#create_account-type
  STRIPE_ACCOUNT_TYPE_EXPRESS = "express"

  # Stripe Connect Account capabilities
  # See https://stripe.com/docs/connect/account-capabilities
  TAXES_1099_MISC_CAPABILITY = "tax_reporting_us_1099_misc"

  # Stripe currency payout threshold can be found here:
  # https://stripe.com/docs/payouts#minimum-payout-amounts
  # The amounts have been converted to cents by multiplying by 100.
  PAYOUT_THRESHOLDS_IN_CENTS = T.let({
    eur: 100,
    gbp: 100,
    chf: 500,
    nok: 2000,
    dkk: 2000,
    sek: 2000,
    mxn: 1000,
    myr: 500,
    sgd: 100,
    pln: 500,
    czk: 3000,
    ron: 500,
    bgn: 200,
    huf: 36000,
  }.freeze, T::Hash[Symbol, Integer])

  SUPPORTED_COUNTRIES = T.let(%w[
    AE AG AL AM AR AT AU BA BE BG
    BH BO BR CA CH CI CL CO CR CY
    CZ DE DK DO EC EE EG ES ET FI
    FR GB GH GI GM GR GT GY HK HR
    HU ID IE IL IN IS IT JM JO JP
    KE KH KR KW LC LI LK LT LU LV
    MA MD MG MK MN MO MT MU MX MY
    NA NG NL NO NZ OM PA PE PH PL
    PT PY QA RO RS RW SA SE SG SI
    SK SN SV TH TN TR TT TZ US UY
    UZ VN ZA
    ].freeze, T::Array[String])

  enum :verification_status, {
    unknown: 0, # default value for the database field
    unverified_requirements_past_due: 1,
    unverified_requirements_currently_due: 2,
    unverified_details_not_submitted: 3,
    unverified_no_transfers_capability: 4,
    unverified_no_tax_reporting_capability: 5,
    unverified_no_card_payments_capability: 6,
    unverified: 7,
    verified: 8,
  }, suffix: true

  belongs_to :sponsors_listing, inverse_of: :stripe_connect_accounts
  has_one :sponsorable, through: :sponsors_listing, inverse_of: :stripe_connect_accounts, disable_joins: true
  has_many :ledger_entries, class_name: "Billing::PayoutsLedgerEntry",
    foreign_key: :stripe_connect_account_id, inverse_of: :stripe_connect_account
  has_many :webhooks, foreign_key: :account_id, primary_key: :stripe_account_id,
    class_name: "Billing::StripeWebhook", inverse_of: :account
  # rubocop:todo Rails/InverseOf
  has_many :payout_webhooks, -> { T.unsafe(self).payouts }, foreign_key: :account_id,
    primary_key: :stripe_account_id, class_name: "Billing::StripeWebhook"
  has_one :latest_payout_webhook, -> { T.unsafe(self).payouts.order(id: :desc) }, foreign_key: :account_id,
    primary_key: :stripe_account_id, class_name: "Billing::StripeWebhook"
  # rubocop:enable Rails/InverseOf

  validates :stripe_account_id, :sponsors_listing, presence: true
  validates :stripe_account_id, uniqueness: true
  validate :no_more_than_one_active_account_per_sponsors_listing
  validate :limit_total_accounts_per_sponsors_listing, on: :create

  after_commit :instrument_create, on: :create
  after_commit :instrument_update, on: :update
  after_commit :instrument_destroy, on: :destroy

  scope :verified, -> { verified_verification_status }
  scope :not_verified, -> { not_verified_verification_status }
  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :active_first, -> { order(active: :desc) }
  scope :for_sponsors_listing, ->(listing_or_id) { where(sponsors_listing_id: listing_or_id) }

  scope :ordered_by_ledger_entry_amount, -> do
    left_joins(:ledger_entries).
      group("stripe_connect_accounts.id, stripe_connect_accounts.sponsors_listing_id").
      order("SUM(billing_payouts_ledger_entries.amount_in_subunits) DESC, " \
            "stripe_connect_accounts.sponsors_listing_id DESC")
  end

  scope :excluding_deleted, -> { where(deleted_at: nil) }
  scope :including_deleted, -> { unscope(where: :deleted_at) }
  scope :payouts_enabled, -> { where(payouts_enabled: true) }
  scope :without_email, -> { where(email: nil) }

  default_scope { excluding_deleted }

  PAYOUT_FAILURE_REASONS = T.let(%w(account_closed account_frozen
    bank_account_restricted bank_ownership_changed could_not_process
    debit_not_authorized declined invalid_account_number
    incorrect_account_holder_name no_account unsupported_card
  ).freeze, T::Array[String])

  # All countries where Sponsors is generally available.
  # Accounts in these countries are automatically accepted into the program so they are able
  # to start configuring their SponsorsListing so it can be submitted for later approval.
  # Add new regions here
  sig { returns(T::Array[String]) }
  def self.supported_countries
    SUPPORTED_COUNTRIES
  end

  GA_REGION_NAME_REPLACEMENTS = T.let({
    "Hong Kong" => "Hong Kong SAR",
  }.freeze, T::Hash[String, String])

  sig { returns T::Array[String] }
  def self.ga_regions_names
    supported_country_codes = supported_countries.to_set
    Braintree::Address::CountryNames
      .select { |_, alpha2, _, _| supported_country_codes.include?(alpha2) }
      .map { |country_name, _, _, _| GA_REGION_NAME_REPLACEMENTS[country_name] || country_name }
      .compact
  end

  sig { returns Integer }
  def self.supported_regions_count
    ga_regions_names.count
  end

  # Public: Get a list of country codes for countries that are not supported by Stripe.
  # e.g. "ZW" and "IR".
  sig { returns(T::Array[String]) }
  def self.unsupported_countries
    all_country_codes = TradeControls::Countries.currently_unsanctioned.map { |(_, code, _, _)| code.to_s }
    all_country_codes - supported_countries
  end

  sig { returns(String) }
  def self.stripe_transfer_failure_logs_url
    base_url = GitHub.stripe_connect_dashboard_base_url
    "#{base_url}/logs?success=false&method%5B%5D=post&method%5B%5D=delete&path=%2Fv1%2Ftransfers&direction%5B%5D=self&direction%5B%5D=connect_in"
  end

  sig { params(target_alpha2: T.nilable(String)).returns(T.nilable(String)) }
  def self.country_name_for(target_alpha2)
    return if target_alpha2.blank?

    country_name, _, = Braintree::Address::CountryNames.find do |_, alpha2, _, _|
      alpha2.downcase == target_alpha2.downcase
    end
    country_name
  end

  sig do
    params(listing_or_id: T.any(SponsorsListing, Integer))
      .returns(T::Array[::Billing::PayoutsLedgerEntry])
  end
  def ledger_entries_for_sponsors_listing(listing_or_id)
    ledger_entries.for_sponsors_listing(listing_or_id).to_a
  end

  sig { returns String }
  def truncated_stripe_account_id
    result = stripe_account_id.sub(/^acct_/i, "")
    if result.size > 10
      result = "#{result.first(5)}…#{result.last(5)}"
    end
    result
  end

  sig { returns(String) }
  def to_s
    stripe_account_id
  end

  # Use stripe_account_id (e.g. acct_1ESWn0EQsq43iHhX) for Rails URL construction.
  sig { returns(String) }
  def to_param
    stripe_account_id
  end

  # Public: Get tags to use for DataDog reporting about this Stripe Connect account.
  sig { returns(T::Array[String]) }
  def datadog_tags
    [
      "payable_type:SponsorsListing",
      "active:#{active?}",
      "has_email:#{email.present?}",
      "verification_status:#{verification_status}",
    ]
  end

  sig { params(user: ::User).returns(Promise[T::Boolean]) }
  def async_belongs_to?(user)
    async_sponsors_listing.then do |sponsors_listing|
      next false unless sponsors_listing
      next true if sponsors_listing.sponsorable_id == user.id && user.user?

      sponsors_listing.async_sponsorable.then do |sponsorable|
        next false unless sponsorable

        sponsorable.adminable_by?(user)
      end
    end
  end

  sig { params(user: ::User).returns(T::Boolean) }
  def belongs_to?(user)
    async_belongs_to?(user).sync
  end

  delegate :sponsorable_id, to: :sponsors_listing, allow_nil: true

  sig { returns(String) }
  def stripe_dashboard_url
    base_url = GitHub.stripe_connect_dashboard_base_url
    "#{base_url}/connect/accounts/#{stripe_account_id}"
  end

  # Public: Calls the Stripe API to generate a new onboarding URL.
  #         This is used for brand new accounts.
  #
  # refresh_url - A String representing the URL Stripe could use to
  #               get a new onboarding URL if the first one expires.
  #
  # return_url - A String representing the URL the user will be redirected
  #              to after they have finished setting up their Stripe account.
  #
  # Raises Stripe::StripeError - See: https://stripe.com/docs/api/errors/handling?lang=ruby
  sig { params(refresh_url: String, return_url: String).returns(String) }
  def stripe_onboarding_url!(refresh_url:, return_url:)
    account_link = ::Stripe::AccountLink.create(
      account: stripe_account_id,
      refresh_url: refresh_url,
      return_url: return_url,
      type: :account_onboarding,
    )

    account_link.url
  end

  # Public: Whether this account has been synced with Stripe at least once or not.
  #         When we first create the account via the Stripe API, `email` is `nil`.
  #         We only have an email after we have fetched the account details from Stripe.
  sig { returns(T::Boolean) }
  def synced?
    email.present?
  end

  # Public: Returns the name of this account's country, e.g., Canada.
  sig { returns(T.nilable(String)) }
  def country_name
    self.class.country_name_for(country)
  end

  sig { params(viewer: T.nilable(::User)).returns(Promise[T::Boolean]) }
  def async_adminable_by?(viewer)
    return Promise.resolve(T.let(false, T::Boolean)) unless viewer

    async_sponsors_listing.then do |sponsors_listing|
      next false unless sponsors_listing
      sponsors_listing.async_adminable_by?(viewer)
    end
  end

  # Public: Get the emoji alias that represents this Stripe Connect account's country.
  #
  # When a non-nil value is returned, it can be used with Emoji#find_by_alias to get a flag's emoji.
  sig { returns(T.nilable(String)) }
  def country_flag_emoji_alias
    SponsorsListing.country_flag_emoji_alias_for(country)
  end

  # Public: Returns the name of this account's billing country, e.g., Canada.
  sig { returns(T.nilable(String)) }
  def billing_country_name
    self.class.country_name_for(billing_country)
  end

  # Public: Are automated payouts disabled for this account?
  sig { returns(T::Boolean) }
  def automated_payouts_disabled?
    payout_interval == "manual"
  end

  # Public: Have we configured payouts for this account?
  #         Either monthly (a.k.a. automatic) or manual (a.k.a. disabled)
  #         A daily interval (or some other interval) means we haven't configured it.
  sig { returns(T::Boolean) }
  def payouts_configured?
    %w(manual monthly).include?(payout_interval)
  end

  # Public: Are monthly payouts allowed for this account?
  sig { returns(T::Boolean) }
  def billing_country_supports_monthly_payouts?
    !!(billing_country.present? && !COUNTRIES_WITHOUT_MONTHLY_PAYOUT_SUPPORT.include?(billing_country))
  end

  # Public: Get information about the US 1099-MISC tax form from Stripe for this account.
  #
  # Returns nil if there was an error getting the status from Stripe.
  sig { returns(T.nilable(Stripe::Capability)) }
  def retrieve_1099_misc_capability
    response = retrieve_capability(
      TAXES_1099_MISC_CAPABILITY
    )
    return unless response.success?

    response.result
  end

  # Public: Request a capability on the Stripe account.
  # See https://stripe.com/docs/api/capabilities/update?lang=ruby
  #
  # capability_id - the String identifier used by Stripe to describe the capability,
  #                 e.g., "card_payments"; see https://stripe.com/docs/connect/account-capabilities
  #
  # Returns a Billing::StripeConnect::Account::APIResult, where the result
  # is a Stripe::Capability like:
  #     {"id": "card_payments", "object": "capability", "requirements": {...
  sig { params(capability_id: String).returns(APIResult) }
  def request_capability(capability_id)
    capability = Stripe::Account.update_capability(stripe_account_id, capability_id,
      requested: true)
    APIResult.success(account: self, result: capability)
  rescue ::Stripe::OAuth::InvalidRequestError,
         ::Stripe::APIConnectionError,
         ::Stripe::StripeError => e
    Failbot.report(e, app: "github-external-request")
    APIResult.failure(account: self, error: e)
  end

  # Public: Get the status of a particular capability on this Stripe account.
  # See https://stripe.com/docs/api/capabilities/retrieve?lang=ruby
  #
  # capability_id - String capability name, e.g., "card_payments"
  #
  # Returns a Billing::StripeConnect::Account::APIResult, where the result
  # is a Stripe::Capability like:
  #     {"id": "card_payments", "object": "capability", "requirements": {...
  sig { params(capability_id: String).returns(APIResult) }
  def retrieve_capability(capability_id)
    capability = Stripe::Account.retrieve_capability(stripe_account_id, capability_id)
    APIResult.success(account: self, result: capability)
  rescue ::Stripe::OAuth::InvalidRequestError,
         ::Stripe::APIConnectionError,
         ::Stripe::StripeError => e
    Failbot.report(e, app: "github-external-request")
    APIResult.failure(account: self, error: e)
  end

  # Public: Get the creation time of the most recent payout for this account.
  sig { returns(T.nilable(DateTime)) }
  def latest_payout_created
    latest_payout_webhook&.stripe_object_created
  end

  # Public: Get the creation time of the most recent payout for this account.
  sig { returns(Promise[T.nilable(DateTime)]) }
  def async_latest_payout_created
    async_latest_payout_webhook.then do |latest_payout_webhook|
      latest_payout_webhook&.stripe_object_created
    end
  end

  # Public: Get information about the latest payout for this Stripe account.
  #
  # See https://stripe.com/docs/api/payouts/retrieve
  #
  # Returns nil when we have no record of a payout, otherwise returns a
  # Billing::StripeConnect::Account::APIResult, where the result
  # is a Stripe::Payout like:
  #     {"id": "po_1HYvqcEQsq43iHhXHu6xVBU7", "object": "payout", "amount": 1100...}
  sig { returns(T.nilable(APIResult)) }
  def latest_payout
    payout_id = latest_payout_webhook&.stripe_object_id
    load_payout(payout_id) if payout_id.present?
  end

  # Public: Check if the most recent payout for this account failed.
  sig { returns(T::Boolean) }
  def latest_payout_failed?
    latest_payout_status == "failed"
  end

  # Public: Get the status from Stripe for the most recent payout for this account.
  #
  # Returns nil if we don't know of any payouts for this account, or if
  # there's an error accessing the Stripe API. Returns a String otherwise;
  # see https://stripe.com/docs/api/payouts/object#payout_object-status.
  sig { returns(T.nilable(String)) }
  def latest_payout_status
    return if payout_webhooks.empty?

    status = Billing::Kv.store.get(latest_payout_status_cache_key).value { nil }
    if status.blank?
      response = latest_payout
      return unless response&.success?

      payout_obj = response.result
      status = payout_obj.status

      ActiveRecord::Base.connected_to(role: :writing) do
        Billing::Kv.store.set(latest_payout_status_cache_key, status, expires: 1.week.from_now)
      end
    end

    status
  end

  sig { params(stripe_account_id: String).returns(String) }
  def self.latest_payout_status_cache_key_for(stripe_account_id)
    "stripe-connect-account-#{stripe_account_id}-latest-payout-status"
  end

  sig { returns(String) }
  def latest_payout_status_cache_key
    self.class.latest_payout_status_cache_key_for(stripe_account_id)
  end

  # Public: The transfers to this Stripe connect account
  #
  # starting_after - optional String representing the transfer id, for pagination
  # ending_before - optional String representing the transfer id, for pagination
  # limit - maximum number of transfers to return
  # sponsor - optional String login to filter transfers by sponsor
  #
  # Returns an Array of ::Billing::Stripe::Transfer
  sig do
    params(
      starting_after: T.nilable(String),
      ending_before: T.nilable(String),
      limit: Integer,
      sponsor: T.nilable(String)
    ).returns(T::Array[Billing::Stripe::Transfer])
  end
  def stripe_transfers(starting_after = nil, ending_before = nil, limit: Billing::Stripe::Transfer::LIMIT, sponsor: nil)
    ::Billing::Stripe::Transfer.list(
      destination: stripe_account_id,
      destination_currency: default_currency,
      starting_after: starting_after,
      ending_before: ending_before,
      limit: limit,
      sponsor: sponsor
    )
  end

  # Public: Can a given user delete this Stripe account?
  sig { params(user: ::User).returns(T::Boolean) }
  def deletable_by?(user)
    sponsors_listing = self.sponsors_listing

    return false unless sponsors_listing
    return false unless user == sponsorable || user.can_admin_sponsors_listings?
    return false if active? && sponsors_listing.approved?
    return false if sponsors_listing.has_balance_in_stripe?(self)
    return false if had_prior_activity? && !user.can_admin_sponsors_listings?

    true
  end

  # Public: Give a explanation of why this account could not be deleted.
  sig { returns(T.nilable(Symbol)) }
  def reason_delete_is_not_allowed
    if active? && sponsors_listing&.approved?
      :active_account
    elsif sponsors_listing&.has_balance_in_stripe?(self)
      :positive_balance
    elsif had_prior_activity?
      :has_received_money
    end
  end

  sig { returns(T::Boolean) }
  def had_prior_activity?
    ledger_entries.any?
  end

  # Public: Make a request to delete the Stripe Connect account.
  #
  # See https://stripe.com/docs/api/accounts/delete
  #
  # Returns a Billing::StripeConnect::Account::APIResult, where the result
  # is a Stripe::Account like:
  #     {"id": "acct_1032D82eZvKYlo2C", "object": "account", "deleted": true}
  sig { returns(APIResult) }
  def delete_stripe_account
    response = Stripe::Account.delete(stripe_account_id)

    APIResult.success(
      account: self,
      result: response
    )
  rescue ::Stripe::OAuth::InvalidRequestError,
         ::Stripe::APIConnectionError,
         ::Stripe::StripeError => e
    Failbot.report(e, app: "github-external-request")
    APIResult.failure(
      account: self,
      error: e,
    )
  end

  # Public: The current balance for this Stripe Connect account.
  #
  # Returns a Billing::StripeConnect::Account::APIResult, where the result
  # is a Stripe::Balance. The `amount` on the Stripe::Balance is in cents/subunits, e.g.,
  # 2600 for $26.00.
  sig { returns(APIResult) }
  memoize def current_balance
    balance_result = ::Stripe::Balance.retrieve(stripe_account: stripe_account_id)
    APIResult.success(account: self, result: balance_result)
  rescue ::Stripe::OAuth::InvalidRequestError,
        ::Stripe::APIConnectionError,
        ::Stripe::StripeError => e
    Failbot.report(e, app: "github-external-request")
    APIResult.failure(account: self, error: e)
  end

  sig { returns(T::Boolean) }
  def balance_available?
    !!(current_balance.result && current_balance.result.available.any?)
  end

  sig { params(target_currency: String).returns(Billing::Money) }
  def balance_amount(target_currency = "usd")
    return ::Billing::Money.new(0) unless balance_available?

    current_balance.result.available.sum(0) { |b| Billing::Money.new(b[:amount], b[:currency]).exchange_to(target_currency) }
  end

  # Public: Load details of a particular payout from Stripe.
  # See https://stripe.com/docs/api/payouts/retrieve?lang=ruby
  #
  # payout_id - String ID for a Stripe payout object, e.g., "po_1J7RrAEQsq43iHhXDBzaINAE"
  # expand - String or Array of Strings for what additional data to load for each payout; defaults to loading the
  #          destination bank account; pass nil to load only the base payout data
  #
  # Returns a Billing::StripeConnect::Account::APIResult, where the result is a Stripe::Payout.
  sig { params(payout_id: String, expand: T.nilable(T.any(String, T::Array[String]))).returns(APIResult) }
  def load_payout(payout_id, expand: "destination")
    expand = [expand] if expand.present? && !expand.is_a?(Array)
    stripe_payout = Stripe::Payout.retrieve({
      id: payout_id,
      expand: expand,
    }, stripe_account: stripe_account_id)

    payout = Billing::Stripe::Payout.new(stripe_payout: stripe_payout, stripe_account_id: stripe_account_id)
    APIResult.success(account: self, result: payout)
  rescue ::Stripe::OAuth::InvalidRequestError,
         ::Stripe::APIConnectionError,
         ::Stripe::StripeError => e
    Failbot.report(e, app: "github-external-request")
    APIResult.failure(account: self, error: e)
  end

  # Public: The payouts that this account has received from Stripe.
  # See https://stripe.com/docs/api/payouts/list?lang=ruby.
  #
  # limit - Limit of results to return.
  # status - Which payout statuses to include; defaults to all;
  #          choose from: pending, paid, failed, canceled
  # include_destination - Whether to include the destination bank information
  #
  # Returns a Billing::StripeConnect::Account::APIResult, where the result
  # is a sorted Array[Stripe::Payout] with the most recent first.
  sig do
    params(
      limit: Integer,
      status: T.nilable(PayoutStatus),
      include_destination: T::Boolean
    ).returns(APIResult)
  end
  def stripe_payouts(limit: 100, status: nil, include_destination: true)
    conditions = { limit: limit }
    conditions[:expand] = ["data.destination"] if include_destination
    conditions[:status] = status.serialize if status

    # Stripe API docs: "The payouts are returned in sorted order, with the most recently created
    # payouts appearing first."
    stripe_result = Stripe::Payout.list(conditions, { stripe_account: stripe_account_id }).data

    result = stripe_result.map do |stripe_payout|
      Billing::Stripe::Payout.new(stripe_payout: stripe_payout, stripe_account_id: stripe_account_id)
    end
    APIResult.success(account: self, result: result)
  rescue ::Stripe::OAuth::InvalidRequestError,
         ::Stripe::APIConnectionError,
         ::Stripe::StripeError => e
    Failbot.report(e, app: "github-external-request")
    APIResult.failure(account: self, error: e)
  end

  # Public: Get a list of the Stripe transactions that went into a given payout.
  # See https://stripe.com/docs/expand/use-cases#charges-in-payout
  # See also https://stripe.com/docs/api/balance_transactions/list
  #
  # stripe_payout_id - a String ID for a Stripe Payout object, e.g., "po_1Gl3ZLLHughnNhxyDrOia0vI"
  # limit - An Integer limit of results to return between 1 and 100
  #
  # Returns a Billing::StripeConnect::Account::APIResult, where the result
  # is a Stripe::ListObject with an Array[Stripe::BalanceTransaction].
  sig { params(stripe_payout_id: String, limit: Integer).returns(APIResult) }
  def stripe_transactions_for_payout(stripe_payout_id, limit: 100)
    balance_transactions = Stripe::BalanceTransaction.list({
      payout: stripe_payout_id,
      type: "payment",
      limit: limit,
      expand: ["data.source.source_transfer"],
    }, stripe_account: stripe_account_id)

    APIResult.success(account: self, result: balance_transactions)
  rescue ::Stripe::APIConnectionError,
         ::Stripe::StripeError,
         ::Stripe::InvalidRequestError => e
    Failbot.report(e, app: "github-external-request")
    APIResult.failure(account: self, error: e)
  end

  # Public: Given updated account information from Stripe, update the relevant fields
  # on this account and save changes.
  #
  # details - a hash from a Stripe::Account object; see https://stripe.com/docs/api/accounts/object?lang=ruby
  sig { params(details: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
  def update_from_stripe(details)
    return true if details.empty?

    assign_from_stripe(details)

    success = T.let(true, T::Boolean)
    transaction do
      if save
        success = sync_country_fields_with_sponsors_listing
        raise ActiveRecord::Rollback unless success
      else
        success = false
      end
    end
    success
  end

  # Public: Given updated account information from Stripe, update the relevant fields
  # on this account and save changes. Raises an exception if the save does not succeed.
  #
  # details - a hash from a Stripe::Account object; see https://stripe.com/docs/api/accounts/object?lang=ruby
  sig { params(details: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
  def update_from_stripe!(details)
    return true if details.empty? # nothing to do

    assign_from_stripe(details)

    success = T.let(true, T::Boolean)
    error_message = T.let(nil, T.nilable(String))

    transaction do
      if save
        unless sync_country_fields_with_sponsors_listing
          sponsors_listing = T.must(self.sponsors_listing)
          listing_errors = sponsors_listing.errors.full_messages
          change_phrases = sponsors_listing.changes.map do |k, v|
            old_value = v.first.to_s
            new_value = v.last.to_s
            "#{k.humanize.downcase} from #{old_value.presence || 'blank'} to #{new_value.presence || 'blank'}"
          end
          changes_summary = change_phrases.join(", ")
          error_message = "Failed to update Sponsors listing for maintainer #{sponsors_listing.sponsorable_login}: " \
            "tried to change #{changes_summary}. Stripe account: #{stripe_account_id}. #{listing_errors.to_sentence}"
          success = false
          raise ActiveRecord::Rollback
        end
      else
        error_message = "Failed to update account from Stripe: #{errors.full_messages.to_sentence}"
        success = false
      end
    end

    raise SyncError.new(error_message) unless success

    success
  end

  # Public: Create manual payout for this Stripe Connect Account
  # See https://stripe.com/docs/api/payouts/create?lang=ruby
  # Returns a Billing::StripeConnect::Account::APIResult, where the result
  # is an Array[Stripe::Payout].
  sig { params(actor: T.nilable(::User), reason: T.nilable(String)).returns(APIResult) }
  def create_payout!(actor: nil, reason: nil)
    balance_resp = current_balance
    raise UnavailableBalanceError unless balance_resp.success?

    balance = balance_resp.result

    metadata = { actor: actor, reason: reason }
    result = balance.available.map do |available|
      response = Stripe::Payout.create(
        { amount: available[:amount], currency: available[:currency], metadata: metadata },
        { stripe_account: stripe_account_id }
      )
    end

    instrument_payout_issued(actor: actor, reason: reason)
    APIResult.success(account: self, result: result)
  rescue ::Stripe::OAuth::InvalidRequestError,
         ::Stripe::APIConnectionError,
         ::Stripe::StripeError => e
    Failbot.report(e, app: "github-external-request")
    APIResult.failure(account: self, error: e)
  end

  # Public: Queues a job to disable automatic payouts for this Stripe Connect account
  sig { params(actor: T.nilable(::User), reason: T.nilable(String)).void }
  def disable_payouts(actor: nil, reason: nil)
    ConfigureStripeAccountJob.perform_later(
      self,
      freeze_payouts: true,
      actor: actor,
      reason: reason,
    )
  end

  # Public: Disable automatic payouts for this Stripe Connect account
  sig { params(actor: T.nilable(::User), reason: T.nilable(String)).returns(::Billing::StripeConnect::Account) }
  def disable_payouts!(actor: nil, reason: nil)
    Sponsors::ConfigureStripeAccount.call(
      account: self,
      freeze_payouts: true,
      actor: actor,
      reason: reason,
    )
  end

  # Public: Queues a job to enable automatic payouts for this Stripe Connect account
  sig { params(actor: T.nilable(::User)).void }
  def enable_payouts(actor: nil)
    ConfigureStripeAccountJob.perform_later(
      self,
      freeze_payouts: false,
      actor: actor,
    )
  end

  # Public: Enables automatic payouts for this Stripe Connect account
  sig { params(actor: T.nilable(::User)).returns(::Billing::StripeConnect::Account) }
  def enable_payouts!(actor: nil)
    Sponsors::ConfigureStripeAccount.call(
      account: self,
      freeze_payouts: false,
      actor: actor,
    )
  end

  # Public: Marks all active accounts for this Sponsors listing as inactive and marks this
  # account as active. If marking this account as active fails, rolls back so
  # that previously active accounts remain active.
  sig { returns(T::Boolean) }
  def activate
    return true if active?
    return false unless can_be_activated?
    success = T.let(false, T::Boolean)
    old_active_stripe_account = sponsors_listing&.active_stripe_connect_account

    self.class.transaction do
      self.class.active.for_sponsors_listing(sponsors_listing_id).update_all(active: false)

      if update(active: true)
        success = true
      else
        raise ActiveRecord::Rollback
      end
    end

    if success && old_active_stripe_account
      instrument_active_account_switch(old_stripe_account: old_active_stripe_account)
    end

    success
  end

  # Public: Can we mark this Stripe account as the active one for the Sponsors listing?
  sig { returns(T::Boolean) }
  def can_be_activated?
    !active? && verified_verification_status?
  end

  # Public: Give a human-readable explanation of why this account might not be verified.
  sig { returns(T.nilable(String)) }
  def unverified_explanation
    if requirements_past_due?
      "Identity items past due"
    elsif requirements_currently_due?
      "Identity items due"
    elsif unverified_details_not_submitted_verification_status?
      "Account details haven't been submitted"
    elsif unverified_no_transfers_capability_verification_status?
      "Account not configured to allow transfers"
    elsif unverified_no_tax_reporting_capability_verification_status?
      "Account not configured to support tax reporting"
    elsif unverified_no_card_payments_capability_verification_status?
      "Account not configured to allow card payments"
    elsif !verified_verification_status?
      "Missing details in Stripe Connect account"
    end
  end

  # Public: Give payout threshold for a currency.
  sig { params(currency: T.any(String, Symbol)).returns(Integer) }
  def self.payout_threshold_for(currency)
    PAYOUT_THRESHOLDS_IN_CENTS[currency.to_sym] || 0
  end

  sig { returns(Symbol) }
  def event_prefix; :stripe_connect_account; end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def event_payload
    {
      event_prefix => self,
      :sponsors_listing => sponsors_listing,
      :email => email,
      :default_currency => default_currency,
      :billing_country => billing_country,
      :country => country,
      :payout_interval => payout_interval,
      :disabled_reason => disabled_reason,
      :verified => verified_verification_status?,
      :details_submitted => details_submitted?,
      :current_requirements_deadline => current_requirements_deadline,
      :requirements_eventually_due => requirements_eventually_due?,
      :requirements_past_due => requirements_past_due?,
      :requirements_currently_due => requirements_currently_due?,
      :transfers_capability => transfers_capability?,
      :card_payments_capability => card_payments_capability?,
      :tax_reporting_capability => tax_reporting_capability?,
      :charges_enabled => charges_enabled?,
      :payouts_enabled => payouts_enabled?,
      :active => active?,
    }
  end

  sig { params(prefix: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def event_context(prefix: event_prefix)
    {
      prefix => stripe_account_id,
      "#{prefix}_id".to_sym => id,
    }
  end

  # Public: Create an audit log event indicating this Stripe account was linked by GitHub staff to a Sponsors listing,
  # rather than the user who owns the Stripe account generating the record in our system themselves.
  sig { params(actor: T.nilable(::User)).void }
  def instrument_link_account(actor)
    payload = GitHub.guarded_audit_log_staff_actor_entry(actor).merge(T.must(sponsorable).event_context)
    instrument(:link_account, payload)
  end

  # Public: Mark this account as deleted while leaving the record in the database.
  sig { returns(T::Boolean) }
  def soft_delete
    touch(:deleted_at)
  end

  # Public: Check if account has been soft-deleted.
  sig { returns(T::Boolean) }
  def deleted?
    deleted_at.present?
  end

  # Public: Check if this Stripe account requires W8 or W9 tax document verification from Stripe.
  #
  # See https://support.stripe.com/questions/general-information-about-us-tax-form-collection-for-stripe
  sig { returns(T::Boolean) }
  def w8_or_w9_verification_required?
    sponsorable && w8_or_w9_requested_at.present?
  end

  # Public: Obtain a lock for this account to prevent simultaneous updates.
  sig { params(block: T.proc.returns(T.untyped)).returns(T.untyped) }
  def with_lock(&block)
    return block.call unless GitHub.flipper[:stripe_connect_account_lock].enabled?(sponsorable)
    restraint = GitHub::Restraint.new
    lock_key = "stripe-#{stripe_account_id}-sync"
    lock_concurrency = 1
    ttl = 10.minutes
    restraint.lock!(lock_key, lock_concurrency, ttl) do
      block.call
    end
  end

  private

  # Private: Update this Stripe account's Sponsors listing so its billing country and residence country match this
  # Stripe account's, if this Stripe account is the active one for the listing.
  sig { returns(T::Boolean) }
  def sync_country_fields_with_sponsors_listing
    # Don't persist changes we learned from Stripe to the Sponsors listing unless the Stripe account is the
    # active one for the listing. Modifying the country of residence has downstream effects on required tax
    # documents, so we want to make sure the Stripe account is completed and activated before we make changes
    # to the listing:
    return true unless active?

    sponsors_listing = self.sponsors_listing
    # Nothing more to do if the Sponsors listing has been deleted:
    return true unless sponsors_listing

    if billing_country.present? && country.present?
      sponsors_listing.update(billing_country: billing_country, country_of_residence: country)
    elsif billing_country.present?
      sponsors_listing.update(billing_country: billing_country)
    elsif country.present?
      sponsors_listing.update(country_of_residence: country)
    else
      true
    end
  end

  sig { void }
  def instrument_create
    # Hydro
    GlobalInstrumenter.instrument("sponsors.stripe_connect_account_create",
      stripe_connect_account: self,
      sponsors_listing: sponsors_listing,
      sponsorable: sponsorable,
      sponsors_listing_stafftools_metadata: sponsors_listing&.stafftools_metadata,
    )
  end

  sig { void }
  def instrument_update
    # Hydro
    GlobalInstrumenter.instrument("sponsors.stripe_connect_account_update",
      stripe_connect_account: self,
      sponsors_listing: sponsors_listing,
      sponsorable: sponsorable,
      sponsors_listing_stafftools_metadata: sponsors_listing&.stafftools_metadata,
    )
  end

  sig { void }
  def instrument_destroy
    # Hydro
    GlobalInstrumenter.instrument("sponsors.stripe_connect_account_delete",
      stripe_connect_account: self,
      sponsors_listing: sponsors_listing,
      sponsorable: sponsorable,
      sponsors_listing_stafftools_metadata: sponsors_listing&.stafftools_metadata,
    )
  end

  sig { params(old_stripe_account: T.nilable(::Billing::StripeConnect::Account)).void }
  def instrument_active_account_switch(old_stripe_account:)
    return unless active?

    # Hydro
    GlobalInstrumenter.instrument("sponsors.active_stripe_connect_account_switch",
      new_active_stripe_connect_account: self,
      old_active_stripe_connect_account: old_stripe_account,
      sponsors_listing: sponsors_listing,
      sponsorable: sponsorable,
      sponsors_listing_stafftools_metadata: sponsors_listing&.stafftools_metadata,
    )
  end

  # Private: Given updated account information from Stripe, update the relevant fields
  # on this account. Does not save changes.
  #
  # details - a hash from a Stripe::Account object; see https://stripe.com/docs/api/accounts/object?lang=ruby
  sig { params(raw_details: T::Hash[T.untyped, T.untyped]).void }
  def assign_from_stripe(raw_details)
    details = HashWithIndifferentAccess.new(raw_details)
    self.email = details["email"].presence
    self.default_currency = details["default_currency"].presence
    self.payout_interval = details.dig("settings", "payouts", "schedule", "interval")
    self.disabled_reason = details.dig("requirements", "disabled_reason")
    self.country = details["country"].presence
    self.charges_enabled = details["charges_enabled"] || false
    self.payouts_enabled = details["payouts_enabled"] || false
    self.details_submitted = details["details_submitted"] || false

    # See https://stripe.com/docs/connect/account-capabilities
    self.transfers_capability = stripe_has_transfers_capability?(details)
    self.card_payments_capability = stripe_has_card_payments_capability?(details)
    self.tax_reporting_capability = stripe_has_tax_reporting_capability?(details)

    timestamp = details.dig("requirements", "current_deadline")
    self.current_requirements_deadline = timestamp ? Time.at(timestamp) : nil

    assign_stripe_w8_or_w9_details(details)
    self.billing_country = external_account_country_from(details)
    self.verification_status = verification_status_from(details)
    self.requirements_eventually_due = stripe_details_has_requirement?(details, "eventually_due")
    self.requirements_currently_due = stripe_details_has_requirement?(details, "currently_due")
    self.requirements_past_due = stripe_details_has_requirement?(details, "past_due")
  end

  sig { params(details: T::Hash[T.untyped, T.untyped]).void }
  def assign_stripe_w8_or_w9_details(details)
    if sponsorable
      # https://stripe.com/docs/api/accounts/object#account_object-additional_verifications-us_w8_or_w9
      w8_or_w9_requested_at_timestamp = details.dig("additional_verifications", "us_w8_or_w9", "requested_at")
      self.w8_or_w9_requested_at = w8_or_w9_requested_at_timestamp ? Time.at(w8_or_w9_requested_at_timestamp) : nil
      self.w8_or_w9_verified = details.dig("additional_verifications", "us_w8_or_w9", "status") == "verified"
    end
  end

  sig { params(details: T::Hash[T.untyped, T.untyped], requirement_name: String).returns(T::Boolean) }
  def stripe_details_has_requirement?(details, requirement_name)
    details.dig("requirements", requirement_name).present?
  end

  sig { params(details: T::Hash[T.untyped, T.untyped], capability: String).returns(T::Boolean) }
  def stripe_details_has_capability?(details, capability)
    details.dig("capabilities", capability) == "active"
  end

  # Private: Check if the given Stripe account details represent a Stripe account that has the 'transfers' capability,
  # or an equivalent capability, enabled. Since 2019-03-14, the 'platform_payments' capability was renamed to
  # 'transfers'; see https://stripe.com/docs/api/accounts/retrieve?lang=ruby. We can also treat
  # 'beneficiary_transfers' as equivalent, per a Stripe email exchange, see
  # https://github.com/github/sponsors/issues/2661#issuecomment-885006960.
  #
  # details - a HashWithIndifferentAccess or Hash with String keys
  sig { params(details: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
  def stripe_has_transfers_capability?(details)
    stripe_details_has_capability?(details, "transfers") ||
      stripe_details_has_capability?(details, "platform_payments") ||
      stripe_details_has_capability?(details, "beneficiary_transfers")
  end

  # Private: Check if the given Stripe account details represent a Stripe account that has the
  # 'tax_reporting_us_1099_misc' capability enabled.
  #
  # details - a HashWithIndifferentAccess or Hash with String keys
  sig { params(details: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
  def stripe_has_tax_reporting_capability?(details)
    stripe_details_has_capability?(details, TAXES_1099_MISC_CAPABILITY)
  end

  # Private: Check if the given Stripe account details represent a Stripe account that has the
  # 'card_payments' capability, or an equivalent capability, enabled. In an email exchange with Stripe, we learned
  # we can treat 'legacy_payments' as equivalent, per
  # https://github.com/github/sponsors/issues/2661#issuecomment-885006960.
  #
  # details - a HashWithIndifferentAccess or Hash with String keys
  sig { params(details: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
  def stripe_has_card_payments_capability?(details)
    stripe_details_has_capability?(details, "card_payments") ||
      stripe_details_has_capability?(details, "legacy_payments")
  end

  # Private: Whether we should allow the 'card_payments' capability in order to consider a Stripe account as having
  # been verified.
  #
  # details - a HashWithIndifferentAccess or Hash with String keys
  sig { params(details: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
  def allow_stripe_card_payments_capability?(details)
    details["country"] == "JP" # Only Japanese accounts can use 'card_payments'
  end

  # Private: Whether we should require the 'tax_reporting_us_1099_misc' capability in order to consider a Stripe
  # account as having been verified.
  #
  # details - a HashWithIndifferentAccess or Hash with String keys
  sig { params(details: T::Hash[T.untyped, T.untyped]).returns(T::Boolean) }
  def require_stripe_tax_reporting_capability?(details)
    return false if sponsorable&.uses_sponsors_fiscal_host?

    details["country"] == "US" # 1099-MISC documents only apply to accounts in the United States
  end

  # For individuals, we need to check the verification status and whether requirements are currently due.
  # For companies, verification status is not returned so we only check whether requirements are currently due.
  sig { params(details: T::Hash[String, T.untyped]).returns(Symbol) }
  def verification_status_from(details)
    return :unverified_details_not_submitted unless details["details_submitted"]

    unless stripe_has_transfers_capability?(details)
      if allow_stripe_card_payments_capability?(details)
        return :unverified_no_card_payments_capability unless stripe_has_card_payments_capability?(details)
      else
        return :unverified_no_transfers_capability
      end
    end

    if require_stripe_tax_reporting_capability?(details) && !stripe_has_tax_reporting_capability?(details)
      return :unverified_no_tax_reporting_capability
    end

    return :unverified_requirements_past_due if stripe_details_has_requirement?(details, "past_due")

    if stripe_details_has_requirement?(details, "currently_due")
      return :unverified_requirements_currently_due if stripe_details_has_requirement?(details, "current_deadline")
    end

    :verified
  end

  # Private: Get the country for the first external account (often a bank account) that's tied to a Stripe account.
  # We treat this country as the billing country for the Stripe account.
  #
  # details - a HashWithIndifferentAccess or Hash with String keys
  #
  # Returns a two-character country String, like "US", or nil.
  sig { params(details: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
  def external_account_country_from(details)
    external_accounts_obj = details["external_accounts"] || {}
    external_accounts = external_accounts_obj["data"] || []
    account = external_accounts.first
    return unless account

    country = account["country"].presence
    country&.upcase
  end

  sig { void }
  def no_more_than_one_active_account_per_sponsors_listing
    return unless sponsors_listing_id.present? && active?

    accounts = self.class.active.for_sponsors_listing(sponsors_listing_id)
    accounts = accounts.where.not(id: id) if persisted?
    return if accounts.empty?

    errors.add(:sponsors_listing_id, "already has an active Stripe Connect account")
  end

  sig { void }
  def limit_total_accounts_per_sponsors_listing
    accounts = self.class.for_sponsors_listing(sponsors_listing_id)
    if accounts.count >= MAX_ACCOUNTS_PER_SPONSORS_LISTING
      errors.add(:sponsors_listing_id, "has reached the limit for Stripe Connect accounts")
    end
  end

  sig { params(actor: T.nilable(::User), reason: T.nilable(String)).void }
  def instrument_payout_issued(actor:, reason:)
    sponsors_listing = self.sponsors_listing
    return unless sponsors_listing

    payload = GitHub.guarded_audit_log_staff_actor_entry(actor).merge(event_context)
    payload = payload.merge(reason: reason) if reason.present?

    # Audit log
    sponsors_listing.instrument(:issue_manual_payout, payload)

    # Hydro
    GlobalInstrumenter.instrument("sponsors.issue_manual_payout",
      listing: sponsors_listing,
      actor: actor,
      reason: reason,
      stripe_account_id: stripe_account_id,
      sponsorable: sponsorable,
      listing_stafftools_metadata: sponsors_listing.stafftools_metadata,
      stripe_connect_account: self,
    )
  end
end
