# typed: true
# frozen_string_literal: true

module SponsorsListing::StripeDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { SponsorsListing }

  included do
    T.bind(self, T.class_of(SponsorsListing))

    has_one :active_stripe_connect_account, -> do
      T.bind(self, T.untyped)
      active
    end, class_name: "Billing::StripeConnect::Account"

    # Public: Get the active Stripe account of the parent listing, if this listing has a parent and if that parent has
    # an active Stripe account. The parent listing will be the fiscal host's SponsorsListing, or nil. A non-nil
    # parent_listing means this listing is fiscally hosted.
    has_one :active_parent_stripe_connect_account,
      through: :parent_listing,
      source: :active_stripe_connect_account,
      disable_joins: true,
      class_name: "Billing::StripeConnect::Account"

    has_many :stripe_connect_accounts, class_name: "Billing::StripeConnect::Account", inverse_of: :sponsors_listing
    has_many :ledger_entries, class_name: "Billing::PayoutsLedgerEntry"
    has_many :transfer_ledger_entries, -> do
      T.bind(self, T.untyped)
      net_transfers
    end, class_name: "Billing::PayoutsLedgerEntry"
    has_many :matches_ledger_entries, -> do
      T.bind(self, T.untyped)
      net_sponsors_matches
    end, class_name: "Billing::PayoutsLedgerEntry"

    scope :stripe_verified, -> do
      relevant_listing_ids = scoped.pluck(:id)
      verified_listing_ids = Billing::StripeConnect::Account
        .verified
        .for_sponsors_listing(relevant_listing_ids)
        .pluck(:sponsors_listing_id)
      where(id: verified_listing_ids)
    end

    scope :not_stripe_verified, -> do
      relevant_listing_ids = scoped.pluck(:id)
      unverified_listing_ids = Billing::StripeConnect::Account
        .not_verified
        .for_sponsors_listing(relevant_listing_ids)
        .pluck(:sponsors_listing_id)
      where(id: unverified_listing_ids)
    end

    scope :payouts_enabled, -> do
      listing_ids = scoped.pluck(:id)
      payouts_enabled_listing_ids = Billing::StripeConnect::Account.payouts_enabled
        .for_sponsors_listing(listing_ids).pluck(:sponsors_listing_id)
      where(id: payouts_enabled_listing_ids)
    end
  end

  # Public: Creates a brand new Stripe account by calling the Stripe API and
  #         using the response to create a new StripeConnect::Account record
  #         associated with this Sponsors Listing.
  #
  #         We explicitly don't set Stripe capabilities, recipient agreements,
  #         nor country as part of the API call so that we can leverage the
  #         defaults defined in the Stripe admin dashboard.
  #         See: https://dashboard.stripe.com/settings/connect/express
  #
  # Raises Stripe::StripeError - See: https://stripe.com/docs/api/errors/handling?lang=ruby
  sig { returns(::Billing::StripeConnect::Account) }
  def create_stripe_account!
    params = {
      type: Billing::StripeConnect::Account::STRIPE_ACCOUNT_TYPE_EXPRESS,
      email: contact_email_address,
      business_type: sponsorable&.sponsors_stripe_business_type,
      settings: {
        payouts: { schedule: stripe_payouts_schedule },
      },
      metadata: {
        stafftools_url: UrlHelpers.stafftools_sponsors_find_listing_url(
          sponsorable&.sponsors_listing&.id,
          host: GitHub.host_name,
        ),
      },
      additional_verifications: {
        us_w8_or_w9: {
          requested: true,
          upfront: [{ disables: "payouts_and_payments" }],
          w8: { type: :substitute },
        }
      }
    }

    resp = ::Stripe::Account.create(params)

    stripe_connect_accounts.create!(
      stripe_account_id: resp.id,
      active: !active_stripe_connect_account.present?,
    )
  end

  # Public: Get the account ID for the Stripe account we should transfer money to for this listing.
  # Can be the personal Stripe account for the maintainer, or the Stripe account for the
  # fiscal host this maintainer uses.
  sig { returns(T.nilable(String)) }
  def stripe_transfer_account_id
    stripe_transfer_account&.stripe_account_id
  end

  # Public: The currency code for this active Stripe account that is personally tied to this Sponsors listing, if
  # any. Will not return the currency code for the fiscal host's Stripe account, if this listing uses a fiscal host.
  #
  # Returns a String like "USD" or nil.
  sig { returns(T.nilable(String)) }
  def active_stripe_connect_account_default_currency
    active_stripe_connect_account&.default_currency&.upcase
  end

  # Public: Get our best guess for the currency the maintainer prefers to use.
  #
  # Returns a three-character String currency code, e.g., "USD", "EUR".
  sig { returns(String) }
  def preferred_currency_code
    return @preferred_currency_code if defined?(@preferred_currency_code)

    # Only check the maintainer's personally owned Stripe account, not any Stripe account owned
    # by the fiscal host, since the fiscal host's preferred currency isn't necessarily the same
    # as the maintainer's:
    @preferred_currency_code = active_stripe_connect_account_default_currency ||
      GitHub::Billing::Currency.currency_of(billing_country)
  end

  # Public: Get the current balance for this listing's active Stripe Connect account based on
  # ledger entries we have recorded. Will be returned in the maintainer's preferred currency.
  # Will also check the parent listing's Stripe Connect account when this listing does not have its
  # own, filtering to just the parent listing's ledger entries that were recorded for this listing.
  sig { returns(Billing::Money) }
  def active_stripe_account_balance
    stripe_account_balance(stripe_connect_account_ids_for_ledger_entries)
  end

  # Public: Get the current balance for this listing's active Stripe Connect account based on
  # ledger entries we have recorded. Does not resolve parent listing ledger entries, checks
  # visibility based on viewer (returning a 0 Billing::Money if not visible), and converts to
  # the default currency.
  #
  # viewer - currently authenticated User or nil
  #
  # A return value of $0 can also indicate the viewer is not allowed to see the actual amount.
  sig { params(viewer: T.nilable(User)).returns(Promise[Billing::Money]) }
  def async_active_stripe_account_balance_visible_to(viewer)
    async_sponsorable.then do |sponsorable|
      next Billing::Money.zero unless sponsorable
      sponsorable.async_adminable_by?(viewer).then do |is_adminable|
        next Billing::Money.zero unless is_adminable
        async_active_stripe_connect_account.then do |stripe_account|
          next Billing::Money.zero unless stripe_account
          balance = stripe_account_balance([stripe_account])
          balance.exchange_to(Billing::Money.default_currency)
        end
      end
    end
  end

  # Public: Get the estimated last payout amount for this listing's active Stripe Connect account
  # based on ledger entries we have recorded. Will be returned in the maintainer's preferred currency.
  # Will also check the parent listing's Stripe Connect account when this listing does not have its
  # own, filtering to just the parent listing's ledger entries that were recorded for this listing.
  #
  # A return value of nil indicates there hasn't been a payout.
  sig { returns(T.nilable(Billing::Money)) }
  def active_stripe_account_estimated_last_payout_balance
    stripe_account = active_stripe_account_for_self_or_fiscal_host
    return unless stripe_account

    latest_payout_date, prev_payout_date = stripe_account.payout_webhooks
      .most_recent_first
      .first(2)
      .map(&:stripe_object_created)
      .compact

    return unless latest_payout_date

    stripe_account_balance(stripe_connect_account_ids_for_ledger_entries,
      date_range: prev_payout_date..latest_payout_date,
    )
  end

  # Public: Returns a two-character country code for the Stripe account's country, e.g., US.
  sig { returns(T.nilable(String)) }
  def stripe_country
    active_stripe_connect_account&.country
  end

  # Public: Get the emoji alias that represents this listing's active Stripe Connect account's country.
  #
  # When a non-nil value is returned, it can be used with Emoji#find_by_alias to get a flag's emoji.
  #
  # Returns a String like "us" or "canada", or nil.
  sig { returns(T.nilable(String)) }
  def stripe_country_flag_emoji_alias
    return @stripe_country_flag_emoji_alias if defined?(@stripe_country_flag_emoji_alias)
    @stripe_country_flag_emoji_alias = active_stripe_connect_account&.country_flag_emoji_alias
  end

  # Public: Returns the name of the Stripe account's country, e.g., Canada.
  sig { returns(T.nilable(String)) }
  def stripe_country_name
    active_stripe_connect_account&.country_name
  end

  sig { returns(T.nilable(String)) }
  def stripe_dashboard_url
    active_stripe_connect_account&.stripe_dashboard_url
  end

  # Public: Is the Stripe account for this listing verified by Stripe?
  sig { returns T.nilable(T::Boolean) }
  def stripe_verified?
    stripe_transfer_account&.verified_verification_status?
  end

  sig { returns T::Boolean }
  def within_stripe_account_limit?
    stripe_connect_accounts.count < Billing::StripeConnect::Account::MAX_ACCOUNTS_PER_SPONSORS_LISTING
  end

  # Public: Determine if we are still waiting to see if the user needs to verify their tax info on Stripe
  #
  # We use `Billing::StripeConnect::Account#w8_or_w9_requested_at` to determine if the listing must use Stripe for
  # tax verification, but we don't get that field back until the Stripe account is created and synced. So if the
  # account doesn't exist or isn't synced we need to wait until it is so we know if the user needs to use DocuSign or
  # Stripe.
  sig { returns(T::Boolean) }
  def waiting_to_see_if_stripe_tax_verification_is_required?
    active_stripe_connect_account.nil? || !T.must(active_stripe_connect_account).synced?
  end

  # Public: Is the listing's billing country supported by Stripe Connect?
  sig { returns(T::Boolean) }
  def eligible_for_stripe_connect?
    return false unless billing_country.present?
    Billing::StripeConnect::Account.supported_countries.include?(billing_country)
  end

  # Public: Does the sponsorable have the ability to get paid via Stripe for Sponsors donations?
  sig { returns T.nilable(T::Boolean) }
  def payouts_enabled?
    active_stripe_connect_account&.payouts_enabled?
  end

  # Public: Get a list of payouts made to any of this listing's Stripe Connect accounts sorted by date created.
  #
  # limit - an Integer limit of results per Stripe account to return.
  # status - a Billing::StripeConnect::Account::PayoutStatus or
  #          for which payout status to include; defaults to paid only
  # include_destination - whether to include the destination bank information
  #
  # The results are sorted by the payout's date created with the most recent payout first.
  sig do
    params(
      limit: Integer,
      status: T.nilable(Billing::StripeConnect::Account::PayoutStatus),
      include_destination: T::Boolean
    ).returns(T::Array[Billing::Stripe::Payout])
  end
  def stripe_payouts_sorted_by_created(
    limit: 100,
    status: Billing::StripeConnect::Account::PayoutStatus::Paid,
    include_destination: true
  )
    all_stripe_accounts = ([active_stripe_connect_account] + stripe_connect_accounts.inactive).compact
    payouts = all_stripe_accounts.flat_map do |account|
      response = account.stripe_payouts(limit: limit, status: status, include_destination: include_destination)
      next unless response.success? && response.result.present?
      response.result
    end
    payouts.compact.sort_by(&:created).reverse
  end

  # Public: Get a list of payouts grouped by year, made to any of this listing's Stripe Connect accounts.
  #
  # limit - an Integer limit of payout results per Stripe account to return.
  # status - a Billing::StripeConnect::Account::PayoutStatus or
  #          for which payout status to include; defaults to paid only
  # include_destination - whether to include the destination bank information; defaults to true
  #
  # Returns a Hash[Integer Year] => Array of Stripe::Payout objects.
  sig do
    params(
      limit: Integer,
      status: T.nilable(Billing::StripeConnect::Account::PayoutStatus),
      include_destination: T::Boolean
    ).returns(T::Hash[Integer, T::Array[Stripe::Payout]])
  end
  def total_paid_out_by_year(
    limit: 100,
    status: Billing::StripeConnect::Account::PayoutStatus::Paid,
    include_destination: true
  )
    all_payouts = stripe_connect_accounts.each_with_object([]) do |account, payouts|
      response = account.stripe_payouts(limit: limit, status: status, include_destination: include_destination)
      if response.success?
        payouts_to_append = response.result
        payouts.concat(payouts_to_append) if payouts_to_append.present?
      end
      payouts
    end

    payouts_by_year = all_payouts.group_by { |payout| Time.at(payout.created).utc.year }

    payouts_by_year.each_with_object({}) do |(year, payouts), total_by_year|
      total_by_year[year] = payouts.sum do |payout|
        Billing::Money.new(payout.amount, payout.currency).exchange_to(preferred_currency_code)
      end
    end
  end

  sig { void }
  def enable_payouts_for_active_stripe_connect_account
    active_stripe_connect_account&.enable_payouts(actor: actor)
  end

  sig { params(reason: T.nilable(String)).void }
  def disable_payouts_for_active_stripe_connect_account(reason: nil)
    active_stripe_connect_account&.disable_payouts(actor: actor, reason: reason)
  end

  # Public: Get the Stripe account associated with this listing in particular or with
  # the parent listing, if this listing uses a fiscal host.
  sig { returns(T.nilable(Billing::StripeConnect::Account)) }
  def active_stripe_account_for_self_or_fiscal_host
    if parent_listing_id
      active_parent_stripe_connect_account
    elsif active_stripe_connect_account
      active_stripe_connect_account
    end
  end

  # Public: Get all the Billing::StripeConnect::Account database IDs for Stripe accounts
  # that are somehow tied to this listing.
  #
  # Returns an Set of Integer database IDs.
  sig { returns(T::Set[Integer]) }
  def stripe_connect_account_ids_for_self_or_fiscal_host
    return Set.new if new_record?

    listing_ids = [id]
    listing_ids << parent_listing_id if parent_listing_id
    account_ids = Billing::StripeConnect::Account.including_deleted.for_sponsors_listing(listing_ids).pluck(:id)
    Set.new(account_ids)
  end

  class BalanceCheckError < StandardError; end

  # Public: Does this Sponsors profile have any money in Stripe? Will consider money for this
  # listing that was put in this listing's fiscal host's Stripe account, if one exists.
  #
  # stripe_accounts_or_ids - specify a particular Billing::StripeConnect::Account, its ID, or a list
  #                          of either whose balance should be retrieved, or default to any relevant
  #                          accounts for this listing
  sig do
    params(
      stripe_accounts_or_ids: T.nilable(T.any(Billing::StripeConnect::Account, Integer,
        T::Array[T.any(Billing::StripeConnect::Account, Integer)]))
    ).returns(T::Boolean)
  end
  def has_balance_in_stripe?(stripe_accounts_or_ids = nil)
    balance = if stripe_accounts_or_ids.present?
      stripe_account_balance(stripe_accounts_or_ids)
    else
      active_stripe_account_balance
    end
    balance.cents > 0
  end

  sig { void }
  def deactivate_all_stripe_accounts
    stripe_connect_accounts.each do |stripe_account|
      # It is ok if we fail to deactivate a Stripe account because we have logic
      # to ensure only one active Stripe account is allowed. We still want to
      # report the issue though so that we can figure out why it failed.
      unless stripe_account.update(active: false)
        error = StandardError.new("Failed to deactivate Stripe account.")
        Failbot.report(
          StandardError.new("Failed to deactivate Stripe account."),
          stripe_account_id: stripe_account.id,
          error_messages: stripe_account.errors.full_messages.to_sentence)
      end
    end
  end

  # Public: Delete the Stripe Connect account on Stripe as well as soft-deleting our record of it.
  #
  # stripe_account - a Billing::StripeConnect::Account associated with this Sponsors listing
  #
  # Returns true on success, false if the account could not be deleted.
  sig { params(stripe_account: T.nilable(Billing::StripeConnect::Account)).returns(T::Boolean) }
  def delete_stripe_account(stripe_account)
    return false unless stripe_account&.persisted?
    return false unless stripe_connect_account_ids_for_self_or_fiscal_host.include?(T.must(stripe_account.id))

    response = stripe_account.delete_stripe_account
    return false unless response.success?

    # Make sure the account is deleted on the Stripe side
    result = response.result
    return false unless result["deleted"]

    # Soft delete Stripe account on our side
    return false unless stripe_account.soft_delete

    update(stripe_authorization_code: nil)
  end

  # Public: For sponsorables that we have Stripe issue tax forms to, does Stripe
  # have all the information/signatures they need from that person such that they
  # can issue tax forms?
  #
  # capability - optional Stripe::Capability for "tax_reporting_us_1099_misc";
  #              a Stripe API request will be made if one is not provided
  sig { params(capability: T.nilable(Stripe::Capability)).returns(T::Boolean) }
  def stripe_tax_forms_completed?(capability: nil)
    capability_id = Billing::StripeConnect::Account::TAXES_1099_MISC_CAPABILITY
    if capability && capability.id != capability_id
      raise "wrong Stripe capability given, expected #{capability_id}, " \
        "got #{capability.id}"
    end
    return false unless eligible_for_stripe_taxes?
    return false unless stripe_transfers_enabled?

    unless capability
      stripe_account = T.must_because(active_stripe_connect_account) do
        "#eligible_for_stripe_taxes? ensures not fiscally hosted and #stripe_transfers_enabled? ensures we have " \
          "an active Stripe Connect account"
      end
      capability = stripe_account.retrieve_1099_misc_capability
    end
    return false unless capability && T.unsafe(capability).requested?

    due_requirements = T.unsafe(capability).requirements.currently_due
    due_requirements.empty?
  end

  # Public: Checks if this listing has its own Stripe account that we can transfer money to,
  # or if it uses a fiscal host that has a Stripe account.
  sig { returns(T::Boolean) }
  def stripe_transfers_enabled?
    stripe_transfer_account.present?
  end

  # Public: Get the Stripe account that should be used for Stripe transfers for this Sponsors
  # listing.
  sig { returns(T.nilable(Billing::StripeConnect::Account)) }
  def stripe_transfer_account
    active_stripe_account_for_self_or_fiscal_host
  end

  # Public: Check if this listing is from the US.
  sig { returns(T::Boolean) }
  def united_states_country?
    tax_country = if stripe_country.present?
      stripe_country
    else
      country_of_residence
    end

    tax_country == "US"
  end

  # Public: Can we issue 1099-MISC forms via Stripe for this Sponsors listing?
  #
  # We only need to issue these forms for sponsorables in the US.
  sig { returns(T::Boolean) }
  def eligible_for_stripe_taxes?
    return false unless has_country_of_residence?
    return false if uses_fiscal_host?
    united_states_country?
  end

  # Public: Get how much matching money GitHub has paid to the maintainer.
  #
  # Returns a positive integer.
  sig { returns(Integer) }
  def total_match_in_cents
    # Multiply by -1 since matches are recorded as negative values, and we want to return a
    # positive amount:
    @total_match_in_cents ||= matches_ledger_entries.sum(:amount_in_subunits) * -1
  end

  private

  # Private: Get the last payout date for this Sponsors listing or its fiscal host.
  sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def last_payout_at_for_self_or_fiscal_host
    if parent_listing_id
      # listings can join a fiscal host, so we use the most recent payout date
      [parent_listing&.last_payout_at, last_payout_at].compact.max
    else
      last_payout_at
    end
  end

  # Private: Get all the database IDs for Stripe Connect accounts that we should check when figuring
  # out the current balance or relevant ledger entries for this listing.
  sig { returns(T::Array[Integer]) }
  def stripe_connect_account_ids_for_ledger_entries
    if parent_listing_id
      # Consider active + inactive Stripe accounts for this listing, but only the active
      # Stripe account for the parent listing:
      stripe_connect_account_ids +
        Billing::StripeConnect::Account.active.for_sponsors_listing(parent_listing_id).pluck(:id)
    elsif association(:active_stripe_connect_account).loaded?
      [active_stripe_connect_account&.id]
    elsif persisted?
      Billing::StripeConnect::Account.active.for_sponsors_listing(id).pluck(:id)
    else
      []
    end
  end

  # Private: Get latest payout to ensure correct next payout date.
  sig { returns(Promise[T.nilable(DateTime)]) }
  def async_latest_payout_created
    async_active_stripe_connect_account.then do |stripe_account|
      next unless stripe_account
      stripe_account.async_latest_payout_created
    end
  end

  # Private: Returns the payout schedule needed by the Stripe API to
  #          create or update an account based on this Sponsors listing.
  sig { returns(T::Hash[Symbol, String]) }
  def stripe_payouts_schedule
    { interval: Billing::StripeConnect::Account::PAYOUT_INTERVAL_MANUAL }
  end

  # Private: Returns the Stripe account balance for a given date range
  #
  # stripe_accounts_or_ids - an Array of Billing::StripeConnect::Accounts or their IDs
  # date_range - a range of dates to to sum the balance. If omitted, the last payout date is used.
  sig do
    params(
      stripe_accounts_or_ids: T.nilable(T.any(Billing::StripeConnect::Account, Integer,
        T::Array[T.any(Billing::StripeConnect::Account, Integer)])),
      date_range: T.nilable(T::Range[DateTime])
    ).returns(Billing::Money)
  end
  def stripe_account_balance(stripe_accounts_or_ids, date_range: nil)
    return Billing::Money.new(0, preferred_currency_code) unless stripe_accounts_or_ids.present?

    transfer_entries = transfer_ledger_entries.for_stripe_account(stripe_accounts_or_ids)

    if date_range
      transfer_entries = transfer_entries.in_date_range(date_range)
    else
      transfer_entries = transfer_entries.since(last_payout_at_for_self_or_fiscal_host)
    end

    transfer_entries_by_currency_code = transfer_entries
      .select(:amount_in_subunits, :currency_code)
      .group(:currency_code)

    balances_by_currency_code = transfer_entries_by_currency_code
      .sum(:amount_in_subunits)
      .sort_by { |_currency_code, balance_amount| -balance_amount }

    if balances_by_currency_code.empty?
      Billing::Money.new(0, preferred_currency_code)
    else
      currency_code_to_exchange_to = T.let(preferred_currency_code, String)

      balances_by_currency_code.sum(0) do |currency_code, cents|
        money = Billing::Money.new(cents, currency_code)

        begin
          money = money.exchange_to(currency_code_to_exchange_to)
        rescue Money::Bank::UnknownRate
          currency_code_to_exchange_to = Billing::Money.default_currency
          money = money.exchange_to(currency_code_to_exchange_to)
        end

        money
      end
    end
  end

  # Private: Delete all Stripe Connect Account related to the listing
  # when listing is removed
  sig { void }
  def mark_stripe_accounts_as_deleted
    stripe_connect_accounts.each(&:soft_delete)
  end
end
