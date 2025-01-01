# typed: strict
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for creating a sponsorship that uses a recurring tier.
module Sponsors
  class CreateRecurringSponsorship < CreateSponsorship
    # tier - the SponsorsTier to be purchased
    # sponsor - who is sponsoring
    # sponsorable - the maintainer being sponsored; defaults to the sponsorable for the given tier
    # viewer - currently authenticated User
    # state - the state of the sponsorship; defaults to "pending"
    # is_public - whether the sponsor's identity should be made public in the new sponsorship
    # email_opt_in - true if the sponsor would like to receive email updates from the sponsorable
    # pay_prorated - whether the first payment for this sponsorship should be prorated
    # sponsorable_metadata - optional user-given metadata for the sponsorship, data the sponsorable may have specified
    # end_date - optional; when the sponsorship should end; only invoiced Zuora sponsors can set this
    # skip_sync - whether to skip the normal plan subscription sync that would occur after subscription item creation
    # payment_source - where this sponsorship is being paid for, either :github or :patreon
    # via_bulk_sponsorship - whether this sponsorship is being created along with others via our Bulk Sponsorship tool
    sig do
      params(
        tier: T.nilable(SponsorsTier),
        sponsor: GitHubSponsors::Types::Sponsor,
        viewer: User,
        sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable),
        state: T.any(String, Symbol, Integer),
        is_public: T.nilable(T::Boolean),
        email_opt_in: T.nilable(T::Boolean),
        pay_prorated: T.nilable(T::Boolean),
        sponsorable_metadata: T.nilable(T::Hash[T.untyped, T.untyped]),
        end_date: T.nilable(Date),
        skip_sync: T.nilable(T::Boolean),
        payment_source: Symbol,
        active_on: T.nilable(Date),
        via_bulk_sponsorship: T::Boolean
      ).returns(Sponsorship)
    end
    def self.call(tier:, sponsor:, viewer:,
      sponsorable: nil,
      state: :pending,
      is_public: true,
      email_opt_in: true,
      pay_prorated: false,
      sponsorable_metadata: nil,
      end_date: nil,
      skip_sync: false,
      payment_source: :github,
      active_on: nil,
      via_bulk_sponsorship: false)
      new(tier: tier, sponsor: sponsor, viewer: viewer, sponsorable: sponsorable, state: state, is_public: is_public,
        email_opt_in: email_opt_in, pay_prorated: pay_prorated, sponsorable_metadata: sponsorable_metadata,
        end_date: end_date, skip_sync: skip_sync, payment_source: payment_source, active_on: active_on,
        via_bulk_sponsorship: via_bulk_sponsorship).call
    end

    sig do
      params(
        tier: T.nilable(SponsorsTier),
        sponsor: GitHubSponsors::Types::Sponsor,
        viewer: User,
        sponsorable: T.nilable(GitHubSponsors::Types::Sponsorable),
        state: T.any(String, Symbol, Integer),
        is_public: T.nilable(T::Boolean),
        email_opt_in: T.nilable(T::Boolean),
        pay_prorated: T.nilable(T::Boolean),
        sponsorable_metadata: T.nilable(T::Hash[T.untyped, T.untyped]),
        end_date: T.nilable(Date),
        skip_sync: T.nilable(T::Boolean),
        payment_source: Symbol,
        active_on: T.nilable(Date),
        via_bulk_sponsorship: T::Boolean
      ).void
    end
    def initialize(tier:, sponsor:, viewer:,
      sponsorable: nil,
      state: :pending,
      is_public: true,
      email_opt_in: true,
      pay_prorated: false,
      sponsorable_metadata: nil,
      end_date: nil,
      skip_sync: false,
      payment_source: :github,
      active_on: nil,
      via_bulk_sponsorship: false
    )
      raise UnprocessableError.new("Did not get a recurring tier") unless tier&.recurring?
      skip_proration = !pay_prorated && sponsor.can_skip_sponsorship_proration?
      super(
        tier: tier,
        sponsor: sponsor,
        sponsorable: sponsorable,
        viewer: viewer,
        state: state,
        is_public: !!is_public,
        email_opt_in: !!email_opt_in,
        pay_prorated: !skip_proration,
        sponsorable_metadata: sponsorable_metadata,
        skip_sync: !!skip_sync,
        payment_source: payment_source,
        active_on: active_on,
        via_bulk_sponsorship: via_bulk_sponsorship,
      )
      @end_date = end_date
    end

    sig { returns(Sponsorship) }
    def call
      super
    end

    private

    sig { void }
    def raise_unless_valid
      super
      verify_end_date_is_in_the_future
      verify_allowed_to_set_end_date
      verify_no_conflicting_active_recurring_sponsorship
      verify_active_on_matches_billing_date
    end

    sig { void }
    def verify_end_date_is_in_the_future
      return unless @end_date
      unless @end_date.future?
        raise UnprocessableError.new("Please choose an end date in the future.")
      end
    end

    sig { void }
    def verify_allowed_to_set_end_date
      return unless @end_date
      unless sponsor.sponsors_invoiced?
        raise UnprocessableError.new("You cannot set an end date for this sponsorship.")
      end
    end

    sig { void }
    def verify_no_conflicting_active_recurring_sponsorship
      return if overriding_patreon_sponsorship_with_github_sponsorship?

      if currently_active_recurring_sponsorship
        raise UnprocessableError.new("An active recurring sponsorship already exists.")
      end
    end

    sig { void }
    def verify_active_on_matches_billing_date
      return unless active_on.present?

      next_sponsors_billing_date = sponsor.next_sponsors_billing_date
      if active_on != next_sponsors_billing_date
        pretty_next_sponsors_billing_date = next_sponsors_billing_date.strftime("%B %e, %Y")
        raise UnprocessableError.new(
          "Sponsorship can only be scheduled to begin on the sponsor's next billing date, " \
            "#{pretty_next_sponsors_billing_date}."
        )
      end
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def create_subscription_item_params
      params = super
      params[:via_bulk_sponsorship] = via_bulk_sponsorship?
      params
    end

    sig { returns T.nilable(Sponsorship) }
    def currently_active_recurring_sponsorship
      return unless sponsorable && tier

      Sponsorship.active
        .recurring
        .from_sponsor(sponsor)
        .with_user_or_org_sponsorable(sponsorable)
        .first
    end

    sig { returns(T::Boolean) }
    def overriding_patreon_sponsorship_with_github_sponsorship?
      return false unless currently_active_recurring_sponsorship&.patreon?
      payment_source == :github
    end

    sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def expiration_time
      @end_date&.end_of_day
    end

    sig { void }
    def after_sponsorship_saved
      super
      trigger_payment_complete_for_patreon_sponsorship
    end

    sig { void }
    def trigger_payment_complete_for_patreon_sponsorship
      # non-Patreon sponsorships have this event triggered when a
      # Billing::BillingTransaction::LineItem is created
      return unless sponsorship.patreon?

      sponsorship.instrument_payment_complete(tier_paid: tier, via_bulk_sponsorship: false)
      sponsorship.touch(:paid_at)
    end
  end
end
