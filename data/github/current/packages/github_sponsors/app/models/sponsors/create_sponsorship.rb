# typed: strict
# frozen_string_literal: true

# Not called directly, but rather is the base class for
# Sponsors::AddOneTimePayment and Sponsors::CreateRecurringSponsorship

module Sponsors
  class CreateSponsorship
    extend T::Sig
    include GitHub::Memoizer

    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    BLOCK_EXCEPTION_MESSAGE = "You can't perform that action at this time."

    sig { returns(T::Array[String]) }
    attr_reader :errors

    # tier - the SponsorsTier to be purchased
    # sponsor - the User or Organization who is sponsoring
    # sponsorable - the User or Organization being sponsored; defaults to the sponsorable for the given tier
    # viewer - currently authenticated User
    # state - the state of the Sponsorship; defaults to "pending"
    # is_public - Boolean indicating whether the sponsor's identity should be made public in the new sponsorship
    # email_opt_in - true if the sponsor would like to receive email updates from the sponsorable
    # pay_prorated - whether the first payment for this sponsorship should be prorated
    # sponsorable_metadata - An optional Hash of user-given metadata for the sponsorship, data the sponsorable may
    #                        have specified
    # skip_sync - Boolean allowing the normal plan subscription sync that occurs after subscription item
    #             creation to be skipped.
    # via_bulk_sponsorship - Boolean indicating whether this sponsorship is being created along with others
    #                        via our Bulk Sponsorship tool
    # payment_source - Symbol representing where payment for this sponsorship is happening, either :github or :patreon
    sig do
      params(
        tier: SponsorsTier,
        sponsor: T.any(User, Organization),
        viewer: T.nilable(User),
        sponsorable: T.nilable(T.any(User, Organization)),
        state: T.any(String, Symbol, Integer),
        is_public: T::Boolean,
        email_opt_in: T::Boolean,
        pay_prorated: T::Boolean,
        sponsorable_metadata: T.nilable(T::Hash[T.any(String, Symbol), T.untyped]),
        skip_sync: T::Boolean,
        via_bulk_sponsorship: T::Boolean,
        payment_source: Symbol,
        active_on: T.nilable(Date),
      ).void
    end
    def initialize(tier:, sponsor:, viewer:,
      sponsorable: nil,
      state: :pending,
      is_public: true,
      email_opt_in: true,
      pay_prorated: false,
      sponsorable_metadata: nil,
      skip_sync: false,
      via_bulk_sponsorship: false,
      payment_source: :github,
      active_on: nil
    )
      @tier = tier
      @sponsor = sponsor
      @sponsorable = T.let(sponsorable || tier.sponsorable, T.nilable(T.any(User, Organization)))
      @viewer = viewer
      @state = state
      @privacy_level = T.let(is_public ? "public" : "private", String)
      @email_opt_in = email_opt_in
      @pay_prorated = pay_prorated
      @sponsorable_metadata = T.let(sponsorable_metadata || {}, T::Hash[T.any(String, Symbol), T.untyped])
      @skip_sync = T.let(!!skip_sync, T::Boolean)
      @errors = T.let([], T::Array[String])
      @via_bulk_sponsorship = T.let(!!via_bulk_sponsorship, T::Boolean)
      @payment_source = payment_source
      @active_on = active_on
    end

    protected

    sig { returns(SponsorsTier) }
    attr_reader :tier

    sig { returns(T.any(User, Organization)) }
    attr_reader :sponsor

    sig { returns(T.nilable(T.any(User, Organization))) }
    attr_reader :sponsorable

    sig { returns(T.nilable(User)) }
    attr_reader :viewer

    sig { returns(T.any(String, Symbol, Integer)) }
    attr_reader :state

    sig { returns(String) }
    attr_reader :privacy_level

    sig { returns(T::Boolean) }
    attr_reader :email_opt_in

    sig { returns(T::Boolean) }
    attr_reader :pay_prorated

    sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
    attr_reader :sponsorable_metadata

    sig { returns(Symbol) }
    attr_reader :payment_source

    sig { returns(T.nilable(Date)) }
    attr_reader :active_on

    sig { returns(Sponsorship) }
    def call
      raise_unless_valid

      success = T.let(false, T::Boolean)

      ApplicationRecord::Domain::Sponsors.transaction do
        success = save_sponsorship

        unless success
          deactivate_subscription_item
          emit_rollback_metrics

          raise ActiveRecord::Rollback unless success
        end
      end

      raise UnprocessableError.new(errors.join(", ")) unless success

      after_sponsorship_saved
      sponsorship
    end

    sig { returns(T::Boolean) }
    def skip_sync?
      @skip_sync
    end

    sig { returns(T::Boolean) }
    def via_bulk_sponsorship?
      @via_bulk_sponsorship
    end

    # Protected: Called before attempting to start the sponsorship to verify the sponsorship should be allowed.
    #
    # Potentially raises Sponsors::CreateSponsorship::UnprocessableError or
    # Sponsors::CreateSponsorship::ForbiddenError. Returns nothing.
    sig { void }
    def raise_unless_valid
      verify_sponsors_enabled
      verify_viewer
      verify_sponsors_listing
      verify_not_blocked
      verify_tier_available_for_sponsorship
      verify_verified_email
      verify_enough_trust_for_sponsorship
    end

    # Protected: Called after the sponsorship is successfully started.
    #
    # Returns nothing.
    sig { void }
    def after_sponsorship_saved
      sponsorship.enqueue_pending_sponsorship_email_job
      sponsorship.instrument_sponsorship_start(via_bulk_sponsorship: via_bulk_sponsorship?)
      update_potential_sponsorship
    end

    sig { void }
    def update_potential_sponsorship
      # Not applicable for bulk sponsorships
      return unless sponsorable

      potential_sponsorship = PotentialSponsorship.with_sponsors_listing_created_state
        .for_potential_sponsor(sponsor)
        .merge(T.must(sponsorable).potential_sponsorships_as_sponsorable)
        .first
      return unless potential_sponsorship

      potential_sponsorship.mark_as_sponsorship_created!
    end

    sig { returns(T.nilable(SponsorsListing)) }
    memoize def listing
      sponsorable&.sponsors_listing
    end

    sig { returns(T.nilable(Sponsorship)) }
    memoize def existing_sponsorship
      Sponsorship.find_by(sponsor: sponsor, sponsorable: sponsorable)
    end

    sig { returns(Sponsorship) }
    memoize def sponsorship
      sponsorship = existing_sponsorship || Sponsorship.new(sponsor: sponsor, sponsorable: sponsorable)

      # See https://github.com/github/sponsors/issues/4764
      # Orgs can re-sponsor someone when they used to use manual transfers, so we clear out old manual transfer
      # data as part of sponsorship creation.
      sponsorship.invoiced_sponsorship_transfer_id = nil

      sponsorship.actor = viewer
      sponsorship.active = true
      sponsorship.tier = tier
      sponsorship.privacy_level = privacy_level
      sponsorship.is_sponsor_opted_in_to_email = email_opt_in
      sponsorship.skip_proration = !pay_prorated
      sponsorship.activated_at = Time.current
      sponsorship.subscribable_selected_at = Time.current
      sponsorship.latest_sponsorable_metadata = sponsorable_metadata
      sponsorship.paid_at = nil
      sponsorship.state = T.unsafe(state)
      sponsorship.payment_source = T.unsafe(payment_source)

      sponsorship
    end

    sig { returns(T::Boolean) }
    def save_sponsorship
      success = build_sponsorship
      return false unless success

      unless sponsorship.save
        error_messages = sponsorship.errors.full_messages

        error_list = error_messages.join(", ")
        @errors << "Could not create sponsorship: #{error_list}"
        return false
      end

      if listing && T.must(listing).payout_probation_started_at.blank?
        unless T.must(listing).update(payout_probation_started_at: Time.zone.now)
          error_list = T.must(listing).errors.full_messages.join(", ")
          @errors << "Could not create sponsorship: #{error_list}"
          return false
        end
      end

      true
    end

    # Protected: Find or construct a Sponsorship record, and any necessary prerequisites, for the new sponsorship.
    #
    # Returns a Boolean to indicate success.
    sig { returns(T::Boolean) }
    def build_sponsorship
      if payment_source == :patreon
        build_patreon_paid_sponsorship
      else
        build_subscription_based_sponsorship
      end
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def create_subscription_item_params
      { tier: tier, sponsor: sponsor, viewer: viewer, skip_sync: skip_sync?, active_on: active_on }
    end

    sig { returns(T.nilable(Billing::SubscriptionItem)) }
    def create_subscription_item
      result = Billing::CreateSponsorshipSubscriptionItem.call(**T.unsafe(create_subscription_item_params))
      result[:subscription_item]
    rescue Billing::CreateSubscriptionItem::UnprocessableError,
           Billing::CreateSubscriptionItem::ForbiddenError => err
      @errors << err.message
      nil
    end

    sig { returns(T::Boolean) }
    def build_subscription_based_sponsorship
      if sponsorship.manual_invoiced? && sponsor.sponsors_invoiced?
        # TODO: this can be removed once all Sponsors-invoiced customers have been migrated
        #
        # When migrating sponsorships from the legacy manual transfer system, we want to allow
        # creating a new subscription-based sponsorship even if they have an existing
        # sponsorship based on manual transfers.
        sponsorship.invoiced_sponsorship_transfer = nil
      end

      subscription_item = create_subscription_item
      return false unless subscription_item

      sponsorship.subscription_item = subscription_item
      sponsorship.expires_at = expiration_time

      true
    end

    sig { returns(T::Boolean) }
    def build_patreon_paid_sponsorship
      sponsorship.expires_at = expiration_time
      sponsorship.payment_source = T.unsafe(:patreon)

      true
    end

    # Protected: the save_sponsorship call above should have created
    # or reactivated a corresponding subscription item; if we can't
    # save this sponsorship, we need to deactivate the subscription
    # item.
    sig { void }
    def deactivate_subscription_item
      if subscription_item = sponsorship.subscription_item
        unless subscription_item.update(quantity: 0)
          error_list = subscription_item.errors.full_messages.join(", ")
          @errors << "unable to deactivate subscription item (#{error_list})"
        end
      end

      # This is part of a synthetic cross-cluster transaction, where
      # we've created the subscription item record and now need to roll
      # it back since something went wrong during sponsorship creation.
      # On creation, the subscription item record will launch a job to
      # synchronize the subscription (adding the sponsorship) and we're
      # hoping that we're able to fix our database before that job
      # runs so that we don't add the untracked subscription item to Zuora.
      # It's important that we log and report that this happened,
      # and in the future we should consider delaying synchronization
      # until after we've got all our ducks sorted :-)
      exception_msg = "Sponsors subscription item rollback initiated"
      error_details = errors.join("; ")
      Failbot.report(StandardError.new(exception_msg),
        errors: error_details,
      )
      GitHub.logger.error(exception_msg,
        "gh.catalog_service": "github/github_sponsors",
        "gh.sponsor.id": @sponsor.id,
        "gh.sponsors_tier.id": @tier.id,
        "exception.details": error_details
      )
    end

    # Protected: Get the expiration time for the new sponsorship.
    #
    # Returns a DateTime or nil.
    sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def expiration_time
      nil
    end

    sig { void }
    def verify_sponsors_enabled
      unless GitHub.sponsors_enabled?
        raise UnprocessableError.new("Could not create sponsorship: GitHub Sponsors is not available")
      end
    end

    sig { void }
    def verify_sponsors_listing
      unless sponsorable.present? && listing.present?
        raise UnprocessableError.new("Could not create sponsorship: Sponsors profile must exist")
      end

      unless T.must(listing).approved?
        raise UnprocessableError.new("Could not create sponsorship: Sponsors profile must be approved")
      end
    end

    sig { void }
    def verify_viewer
      unless viewer
        raise ForbiddenError.new("Could not create sponsorship: cannot sponsor anonymously")
      end

      unless T.must(viewer).user?
        raise ForbiddenError.new("Could not create sponsorship: viewer must be a user")
      end
    end

    sig { void }
    def verify_tier_available_for_sponsorship
      unless tier.available_for_sponsorship?
        raise ForbiddenError.new("Could not create sponsorship")
      end
    end

    sig { void }
    def verify_not_blocked
      return unless sponsorable

      # This is validated at the model level too but we want to provide a better
      # user-visible message that doesn't use the word "block".
      raise ForbiddenError.new(BLOCK_EXCEPTION_MESSAGE) if sponsor.blocked_by?(sponsorable)
      raise ForbiddenError.new(BLOCK_EXCEPTION_MESSAGE) if T.must(sponsorable).blocked_by?(sponsor)
    end

    sig { void }
    def verify_verified_email
      return if viewer == User.staff_user

      # Can't sponsor without a verified email
      if viewer && T.must(viewer).no_verified_emails?
        raise ForbiddenError.new("You need a verified email address in order to sponsor anyone.")
      end
    end

    sig { void }
    def verify_enough_trust_for_sponsorship
      if !Sponsors::TrustSystem.enough_trust_for_sponsorship?(
        actor: viewer,
        sponsor: sponsor,
        sponsorable: sponsorable,
        tier: tier,
      )
        raise ForbiddenError.new(
          "This sponsorship cannot be made at this time. Please reach out to support for more details."
        )
      end
    end

    sig { void }
    def emit_rollback_metrics
      GitHub.dogstats.increment("sponsors.create_sponsorship.failure")
    end
  end
end
