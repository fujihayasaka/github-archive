# typed: strict
# frozen_string_literal: true

module Sponsors
  class AddOneTimePayments
    include GitHub::Memoizer

    DEFAULT_PRIVACY_LEVEL = "public" # default to publicly identifying the sponsor in the sponsorships
    DEFAULT_RECEIVE_EMAIL = false # default to not receiving emails from the maintainers

    # Public: Create multiple sponsorships from the same sponsor for different maintainers.
    #
    # sponsor - the User or Organization who should pay for the sponsorships
    # actor - the User who is signed in and wants to create the sponsorships on behalf of the sponsor
    # amounts_by_sponsorable_login - a Hash where the keys are String User or Organization logins for each
    #                                maintainer to be sponsored, with the value being a String USD amount such as
    #                                "2" for "$2.00"
    # receive_email - a Boolean indicating whether the sponsor wants to receive email from the maintainers
    # privacy_level - a String indicating whether the sponsor wants to be publicly identified as a sponsor; choose
    #                 from 'public' or 'private'
    # state - an Integer indicating the state of the sponsorship; defaults to 0 (pending)
    # after_payment_hook - optional lambda to be called after a one-time payment is made successfully; receives the
    #                      login of the maintainer who got paid
    sig do
      params(
        sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
        actor: T.nilable(User),
        amounts_by_sponsorable_login: T::Hash[String, T.any(String, Integer, Billing::Money)],
        state: T.any(String, Symbol, Integer),
        receive_email: T::Boolean,
        privacy_level: T.any(String, Symbol),
        after_payment_hook: T.nilable(T.proc.params(sponsorable_login: String).void),
      ).returns(Sponsors::AddOneTimePayments::Result)
    end
    def self.call(sponsor:, actor:, amounts_by_sponsorable_login:, state: :pending, receive_email: DEFAULT_RECEIVE_EMAIL, privacy_level: DEFAULT_PRIVACY_LEVEL, after_payment_hook: nil)
      new(
        sponsor: sponsor,
        actor: actor,
        amounts_by_sponsorable_login: amounts_by_sponsorable_login,
        state: state,
        receive_email: receive_email,
        privacy_level: privacy_level,
        after_payment_hook: after_payment_hook,
      ).call
    end

    sig do
      params(
        sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
        actor: T.nilable(User),
        amounts_by_sponsorable_login: T::Hash[String, T.any(String, Integer, Billing::Money)],
        state: T.any(String, Symbol, Integer),
        receive_email: T::Boolean,
        privacy_level: T.any(String, Symbol),
        after_payment_hook: T.nilable(T.proc.params(sponsorable_login: String).void),
      ).void
    end
    def initialize(sponsor:, actor:, amounts_by_sponsorable_login:, state: :pending, receive_email: DEFAULT_RECEIVE_EMAIL, privacy_level: DEFAULT_PRIVACY_LEVEL, after_payment_hook: nil)
      @sponsor = sponsor
      @actor = actor
      @amounts_by_sponsorable_login = amounts_by_sponsorable_login
      @state = state
      @errors = T.let([], T::Array[String])
      @sponsorships = T.let([], T::Array[Sponsorship])
      @subscription_items = T.let([], T::Array[Billing::SubscriptionItem])
      @receive_email = T.let(!!receive_email, T::Boolean)
      @is_public = T.let(privacy_level.to_s.downcase != "private", T::Boolean)
      @custom_tiers_by_row = T.let({}, T::Hash[Sponsors::BulkSponsorshipRow, SponsorsTier])
      @after_payment_hook = after_payment_hook
    end

    sig { returns(Sponsors::AddOneTimePayments::Result) }
    def call
      if validator.valid?
        add_one_time_payments
        synchronize_plan_subscription
        store_new_bulk_sponsorship_event
      else
        errors.concat(validator.errors)
      end
      Sponsors::AddOneTimePayments::Result.new(errors: errors, sponsorships: sponsorships,
        subscription_items: subscription_items)
    end

    private

    sig { returns T.nilable(GitHubSponsors::Types::Sponsor) }
    attr_reader :sponsor

    sig { returns T.nilable(User) }
    attr_reader :actor

    sig { returns T::Hash[String, T.any(String, Integer, Billing::Money)] }
    attr_reader :amounts_by_sponsorable_login

    sig { returns T.any(String, Symbol, Integer) }
    attr_reader :state

    sig { returns T::Array[String] }
    attr_reader :errors

    sig { returns T::Array[Sponsorship] }
    attr_reader :sponsorships

    sig { returns T::Array[Billing::SubscriptionItem] }
    attr_reader :subscription_items

    sig { returns T::Boolean }
    attr_reader :receive_email

    sig { returns T::Boolean }
    attr_reader :is_public

    sig { returns T::Hash[Sponsors::BulkSponsorshipRow, SponsorsTier] }
    attr_reader :custom_tiers_by_row

    sig { returns T.nilable(T.proc.params(sponsorable_login: String).void) }
    attr_reader :after_payment_hook

    sig { returns T::Array[{ sponsorable_login: String, amount: T.any(String, Integer, Billing::Money) }] }
    memoize def amounts_by_sponsorable_login_array
      amounts_by_sponsorable_login.map do |login, amount|
        { sponsorable_login: login, amount: amount }
      end
    end

    sig { returns Sponsors::BulkSponsorshipValidator }
    memoize def validator
      Sponsors::BulkSponsorshipValidator.new(
        sponsor: sponsor,
        actor: actor,
        amounts_by_sponsorable_login: amounts_by_sponsorable_login,
      )
    end

    sig { returns T::Array[Sponsors::BulkSponsorshipRow] }
    memoize def sponsorship_rows
      sponsor = T.must_because(self.sponsor) { "called after Validator ensures sponsor is non-nil" }
      Sponsors::BulkSponsorshipRow.build_rows_from_params(
        amounts_by_sponsorable_login_array: amounts_by_sponsorable_login_array,
        sponsor: sponsor,
        recurring: false,
      )
    end

    sig { void }
    def add_one_time_payments
      sponsorship_rows.each do |row|
        begin
          add_one_time_payment_for(row)
          after_payment_hook&.call(row.sponsorable_login)
        rescue Sponsors::CreateSponsorship::ForbiddenError,
               Sponsors::CreateSponsorship::UnprocessableError,
               Billing::CreateSubscriptionItem::UnprocessableError => err
          errors << err.message
          clean_up_custom_tier_for_failed_row(row)
        rescue Sponsors::CreateSponsorsTier::ForbiddenError, Sponsors::CreateSponsorsTier::UnprocessableError => err
          errors << err.message
        end
      end
    end

    sig { params(row: Sponsors::BulkSponsorshipRow).void }
    def add_one_time_payment_for(row)
      attrs = add_one_time_payment_attributes_for(row)
      return unless attrs

      sponsorship_or_subscription_item = Sponsors::AddOneTimePayment.call(attrs)
      unless sponsorship_or_subscription_item
        errors << "Failed to sponsor #{row.sponsorable_login}"
        clean_up_custom_tier_for_failed_row(row)
        return
      end

      append_successful_one_time_payment_result(sponsorship_or_subscription_item)
    end

    sig { params(row: Sponsors::BulkSponsorshipRow).void }
    def clean_up_custom_tier_for_failed_row(row)
      # Attempt to clean up the newly created custom tier since we weren't able to use it:
      tier = custom_tiers_by_row[row]
      tier.destroy if tier&.custom?
    end

    sig { params(row: Sponsors::BulkSponsorshipRow).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def add_one_time_payment_attributes_for(row)
      tier = find_published_or_create_custom_tier_for(row)
      return unless tier

      {
        tier: tier,
        sponsor: sponsor,
        sponsorable: row.sponsorable,
        viewer: actor,
        state: state,
        is_public: is_public,
        email_opt_in: receive_email,
        skip_sync: true,
        via_bulk_sponsorship: true,
      }
    end

    sig { params(sponsorship_or_subscription_item: T.any(Sponsorship, Billing::SubscriptionItem)).void }
    def append_successful_one_time_payment_result(sponsorship_or_subscription_item)
      if sponsorship_or_subscription_item.is_a?(Sponsorship)
        sponsorships << sponsorship_or_subscription_item
      else
        subscription_items << sponsorship_or_subscription_item
      end
    end

    sig { void }
    def synchronize_plan_subscription
      return if sponsorships.empty? && subscription_items.empty?

      plan_sub = if subscription_items.present?
        T.must(subscription_items.first).plan_subscription
      else
        T.must(sponsorships.first).plan_subscription
      end

      plan_sub&.synchronize_later
    end

    sig { void }
    def store_new_bulk_sponsorship_event
      sponsor = T.must_because(self.sponsor) { "called after Validator ensures sponsor is non-nil" }
      stored_tier_ids = sponsor.payment_incomplete_bulk_sponsorship_tier_ids

      # For new sponsorships
      new_sponsorship_ids = sponsorships.map(&:subscribable_id).to_set

      # For concurrent sponsorships
      new_subscription_item_ids = subscription_items.map(&:subscribable_id).compact.to_set

      new_tier_ids = new_sponsorship_ids + new_subscription_item_ids
      all_tier_ids = stored_tier_ids + new_tier_ids

      sponsor.save_bulk_sponsorship_tier_ids(all_tier_ids)
    end

    sig { returns T.nilable(T::Boolean) }
    memoize def skip_proration?
      sponsor&.can_skip_sponsorship_proration?
    end

    sig { params(row: Sponsors::BulkSponsorshipRow).returns(T.nilable(SponsorsTier)) }
    def find_published_or_create_custom_tier_for(row)
      unless row.amount.cents % 100 == 0
        errors << "Must specify a whole-dollar amount for #{row.sponsorable_login}"
        return
      end

      unless row.valid?
        errors << "#{row.sponsorable_login}: #{row.error_message}"
        return
      end

      existing_tier = row.published_tier
      return existing_tier if existing_tier

      custom_tiers_by_row[row] = Sponsors::CreateSponsorsTier.call(
        custom: true,
        description: nil,
        sponsors_listing: row.approved_sponsors_listing,
        amount: row.dollars, # e.g., 1 for $1.00
        viewer: actor,
        sponsor: sponsor,
        is_recurring: false,
        parent_tier_id: row.parent_tier_for_custom_tier&.id,
      )
    end
  end
end
