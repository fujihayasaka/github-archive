# typed: strict
# frozen_string_literal: true

module Sponsors
  class CreateRecurringSponsorships
    include GitHub::Memoizer

    DEFAULT_PRIVACY_LEVEL = AddOneTimePayments::DEFAULT_PRIVACY_LEVEL
    DEFAULT_RECEIVE_EMAIL = AddOneTimePayments::DEFAULT_RECEIVE_EMAIL

    # Public: Create multiple sponsorships from the same sponsor for different maintainers.
    #
    # sponsor - who should pay for the sponsorships
    # actor - the authenticated user who wants to create the sponsorships on behalf of the sponsor; might be the
    #         sponsor
    # amounts_by_sponsorable_login - a Hash where the keys are maintainer logins to be sponsored, with the value being
    #                                a USD amount such as "2" for $2.00
    # receive_email - whether the sponsor wants to receive email from the maintainers
    # privacy_level - whether the sponsor wants to be publicly identified as a sponsor; choose from 'public' or
    #                 'private'
    # state - the state of the sponsorship; defaults to 0 (pending)
    # end_date - optional; when the sponsorship should end; only invoiced Zuora sponsors can set this
    # after_payment_hook - optional lambda to be called per sponsorship, after it is made successfully; receives the
    #                      login of the maintainer who got paid
    sig do
      params(
        sponsor: T.nilable(GitHubSponsors::Types::Sponsor),
        actor: T.nilable(User),
        amounts_by_sponsorable_login: T::Hash[String, T.any(String, Integer, Billing::Money)],
        state: T.any(String, Symbol, Integer),
        receive_email: T::Boolean,
        privacy_level: T.any(String, Symbol),
        end_date: T.nilable(Date),
        active_on: T.nilable(Date),
        after_payment_hook: T.nilable(T.proc.params(sponsorable_login: String).void),
        pay_prorated: T::Boolean
      ).returns(Sponsors::CreateRecurringSponsorships::Result)
    end
    def self.call(
      sponsor:,
      actor:,
      amounts_by_sponsorable_login:,
      state: :pending,
      receive_email: DEFAULT_RECEIVE_EMAIL,
      privacy_level: DEFAULT_PRIVACY_LEVEL,
      end_date: nil,
      active_on: nil,
      after_payment_hook: nil,
      pay_prorated: true
    )
      new(
        sponsor: sponsor,
        actor: actor,
        amounts_by_sponsorable_login: amounts_by_sponsorable_login,
        state: state,
        receive_email: receive_email,
        privacy_level: privacy_level,
        end_date: end_date,
        active_on: active_on,
        after_payment_hook: after_payment_hook,
        pay_prorated: pay_prorated
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
        end_date: T.nilable(Date),
        active_on: T.nilable(Date),
        after_payment_hook: T.nilable(T.proc.params(sponsorable_login: String).void),
        pay_prorated: T::Boolean
      ).void
    end
    def initialize(
      sponsor:,
      actor:,
      amounts_by_sponsorable_login:,
      state: :pending,
      receive_email: DEFAULT_RECEIVE_EMAIL,
      privacy_level: DEFAULT_PRIVACY_LEVEL,
      end_date: nil,
      active_on: nil,
      after_payment_hook: nil,
      pay_prorated: true
    )
      @sponsor = sponsor
      @actor = actor
      @amounts_by_sponsorable_login = amounts_by_sponsorable_login
      @state = state
      @end_date = end_date
      @active_on = active_on
      @errors = T.let([], T::Array[String])
      @sponsorships = T.let([], T::Array[Sponsorship])
      @subscription_items = T.let([], T::Array[Billing::SubscriptionItem])
      @receive_email = T.let(!!receive_email, T::Boolean)
      @is_public = T.let(privacy_level.to_s.downcase != "private", T::Boolean)
      @custom_tiers_by_row = T.let({}, T::Hash[Sponsors::BulkSponsorshipRow, SponsorsTier])
      @after_payment_hook = after_payment_hook
      @pay_prorated = pay_prorated
    end

    sig { returns(Sponsors::CreateRecurringSponsorships::Result) }
    def call
      if validator.valid?
        create_sponsorships
        synchronize_plan_subscription
        store_new_bulk_sponsorship_event
      else
        errors.concat(validator.errors)
      end
      Sponsors::CreateRecurringSponsorships::Result.new(errors: errors, sponsorships: sponsorships)
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

    sig { returns T::Boolean }
    attr_reader :receive_email

    sig { returns T::Boolean }
    attr_reader :is_public

    sig { returns T::Hash[Sponsors::BulkSponsorshipRow, SponsorsTier] }
    attr_reader :custom_tiers_by_row

    sig { returns(T.nilable(Date)) }
    attr_reader :end_date

    sig { returns T.nilable(T.proc.params(sponsorable_login: String).void) }
    attr_reader :after_payment_hook

    sig { returns Sponsors::BulkSponsorshipValidator }
    memoize def validator
      Sponsors::BulkSponsorshipValidator.new(
        sponsor: sponsor,
        actor: actor,
        amounts_by_sponsorable_login: amounts_by_sponsorable_login,
        end_date: end_date,
      )
    end

    sig { void }
    def create_sponsorships
      sponsorship_rows.each do |row|
        begin
          create_sponsorship_for(row)
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

    sig { void }
    def synchronize_plan_subscription
      return if sponsorships.empty?

      plan_sub = T.must(sponsorships.first).plan_subscription
      plan_sub&.synchronize_later
    end

    sig { void }
    def store_new_bulk_sponsorship_event
      sponsor = T.must_because(self.sponsor) { "called after Validator ensures sponsor is non-nil" }
      stored_tier_ids = sponsor.payment_incomplete_bulk_sponsorship_tier_ids
      new_tier_ids = sponsorships.map(&:subscribable_id).to_set
      all_tier_ids = stored_tier_ids + new_tier_ids
      sponsor.save_bulk_sponsorship_tier_ids(all_tier_ids)
    end

    sig { params(row: Sponsors::BulkSponsorshipRow).void }
    def create_sponsorship_for(row)
      tier = find_published_or_create_custom_tier_for(row)
      return unless tier

      sponsor = T.must_because(self.sponsor) { "called after validator ensures sponsor is non-nil" }
      actor = T.must_because(self.actor) { "called after validator ensures actor is non-nil" }

      sponsorship = Sponsors::CreateRecurringSponsorship.call(
        tier: tier,
        sponsor: sponsor,
        sponsorable: row.sponsorable,
        viewer: actor,
        state: state,
        is_public: is_public,
        email_opt_in: receive_email,
        skip_sync: true,
        end_date: end_date,
        via_bulk_sponsorship: true,
        active_on: @active_on,
        pay_prorated: @pay_prorated
      )
      sponsorships << sponsorship
    end

    sig { returns T::Array[Sponsors::BulkSponsorshipRow] }
    memoize def sponsorship_rows
      sponsor = T.must_because(self.sponsor) { "called after validator ensures sponsor is non-nil" }
      Sponsors::BulkSponsorshipRow.build_rows_from_params(
        amounts_by_sponsorable_login_array: amounts_by_sponsorable_login_array,
        sponsor: sponsor,
        recurring: true,
      )
    end

    sig { returns T::Array[{ sponsorable_login: String, amount: T.any(String, Integer, Billing::Money) }] }
    memoize def amounts_by_sponsorable_login_array
      amounts_by_sponsorable_login.map do |login, amount|
        { sponsorable_login: login, amount: amount }
      end
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
        is_recurring: true,
        parent_tier_id: row.parent_tier_for_custom_tier&.id,
      )
    end

    sig { params(row: Sponsors::BulkSponsorshipRow).void }
    def clean_up_custom_tier_for_failed_row(row)
      # Attempt to clean up the newly created custom tier since we weren't able to use it:
      tier = custom_tiers_by_row[row]
      tier.destroy if tier&.custom?
    end
  end
end
