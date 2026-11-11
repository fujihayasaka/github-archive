# typed: strict
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) used for changing the tier of a sponsorship.
module Sponsors
  class UpdateSponsorshipTier < UpdateSponsorship
    include GitHub::Memoizer

    # sponsorship - the Sponsorship to update
    # new_tier - the new SponsorsTier to use
    # viewer - currently authenticated User
    # sponsorable_metadata - optional Hash of user-given metadata for the sponsorship, data the sponsorable may
    #                        have specified
    # active_on - optional Date when the tier change should take effect. Default behavior is for upgrades to
    #             take effect immediately and downgrades to take effect on the next billing date.
    sig do
      params(
        sponsorship: Sponsorship,
        new_tier: SponsorsTier,
        viewer: T.nilable(User),
        sponsorable_metadata: T.nilable(T::Hash[String, T.untyped]),
        active_on: T.nilable(Date),
      ).returns(Sponsorship)
    end
    def self.call(sponsorship, new_tier:, viewer:, sponsorable_metadata: nil, active_on: nil)
      new(
        sponsorship: sponsorship,
        new_tier: new_tier,
        viewer: viewer,
        sponsorable_metadata: sponsorable_metadata,
        active_on: active_on
      ).call
    end

    sig do
      params(
        new_tier: SponsorsTier,
        viewer: T.nilable(User),
        sponsorship: Sponsorship,
        sponsorable_metadata: T.nilable(T::Hash[String, T.untyped]),
        active_on: T.nilable(Date),
      ).void
    end
    def initialize(new_tier:, viewer:, sponsorship:, sponsorable_metadata: nil, active_on: nil)
      super(sponsorship: sponsorship, viewer: viewer)
      @previous_tier = T.let(T.must(previous_sponsorship.tier), SponsorsTier)
      @sponsor = T.let(T.must(sponsorship.sponsor), T.any(User, Organization))
      @sponsorable = T.let(T.must(sponsorship.sponsorable), T.any(User, Organization))
      @new_tier = new_tier
      @sponsorable_metadata = T.let(sponsorable_metadata || {}, T::Hash[String, T.untyped])
      @old_subscription_item = T.let(sponsorship.subscription_item, T.nilable(Billing::SubscriptionItem))
      @active_on = active_on
    end

    sig { returns(Sponsorship) }
    def call
      super
    end

    private

    sig { void }
    def raise_unless_valid
      super
      verify_new_tier_purchasable
      verify_sponsorship_unlocked
      verify_new_tier_has_same_frequency
      verify_invoiced_customer_balance
      verify_no_pending_downgrade
      verify_no_pending_cancellation
    end

    sig { returns(T::Boolean) }
    def save_sponsorship
      return true unless sponsorship_changed?
      return false unless update_subscription_item
      update_tier_for_patreon
      sponsorship.latest_sponsorable_metadata = @sponsorable_metadata
      super
    end

    sig { void }
    def after_sponsorship_saved
      invite_to_new_tier_repo
      instrument_tier_change_for_patreon
    end

    sig { returns(T::Boolean) }
    def sponsorship_changed?
      return true if tier_changed?
      # Support scheduling future changes that use the same tier, this allows creating a future activation
      # that uses a different billable entity (which will be inferred from the current state of the sponsor).
      #
      # TODO: Consider a `UpdateSponsorshipBilling` or similar to handle the special-case where we want to preserve
      # a tier but change the billable entity associated with the subscription item.
      bill_on = active_on
      return true if bill_on && GitHub::Billing.future?(bill_on)
      false
    end

    sig { returns(T::Boolean) }
    def tier_changed?
      # check amount and frequency instead of tier ids since multiple custom SponsorsTiers can
      # exist at the same amount and frequency.
      amount_changed = previous_tier.monthly_price_in_cents != new_tier.monthly_price_in_cents
      frequency_changed = previous_tier.frequency != new_tier.frequency
      amount_changed || frequency_changed
    end

    sig { returns(T::Boolean) }
    def new_tier_grants_different_repo_access?
      return false if @new_tier.repository_id.nil?
      return false if @new_tier.repository_id == previous_tier.repository_id
      true
    end

    sig { void }
    def invite_to_new_tier_repo
      return unless new_tier_grants_different_repo_access?
      @new_tier.enqueue_grant_repository_access_job_for(@sponsor.id)
    end

    sig { void }
    def update_tier_for_patreon
      # Since we don't have a subscription item for Patreon-paid sponsorships, we need to update the tier here
      if sponsorship.patreon?
        sponsorship.tier = new_tier
      end
    end

    sig { void }
    def instrument_tier_change_for_patreon
      if sponsorship.patreon?
        sponsorship.instrument_tier_change(actor: viewer, previous_tier: previous_tier)
      end
    end

    # Private: Update the subscription item and the sponsorship.
    #
    # Returns a Boolean indicating success.
    sig { returns(T::Boolean) }
    def update_subscription_item
      # Patreon-paid sponsorships will not have a subscription item
      return true if old_subscription_item.nil? && sponsorship.patreon?

      bill_on = active_on
      if bill_on.present? && GitHub::Billing.future?(bill_on)
        schedule_tier_change
      else
        update_tier
      end
    end

    sig { returns T::Boolean }
    def schedule_tier_change
      sub_item_result = begin
        Billing::CreateSponsorshipSubscriptionItem.call(
          tier: new_tier,
          sponsor: sponsor,
          viewer: viewer || User.ghost,
          skip_sync: true,
          via_bulk_sponsorship: false,
          active_on: active_on,
        )
      rescue Billing::CreateSubscriptionItem::UnprocessableError,
             Billing::CreateSubscriptionItem::ForbiddenError => err
        @errors << err.message
        nil
      end

      return false unless sub_item_result && sub_item_result[:subscription_item].present?

      # set up the sponsorship with the pending activation
      sponsorship.subscription_item = sub_item_result[:subscription_item]
      sponsorship.tier = new_tier
      sponsorship.active = true

      true
    end

    sig { returns T::Boolean }
    def update_tier
      update_result = begin
        Billing::UpdateSubscriptionItem.call(
          subscribable: new_tier,
          quantity: 1,
          viewer: viewer,
          plan_subscription: old_subscription_item&.plan_subscription,
        )
      rescue Billing::UpdateSubscriptionItem::UnprocessableError,
             Billing::UpdateSubscriptionItem::ForbiddenError => err
        @errors << err.message
        nil
      end

      if update_result && update_result.result.success
        true
      else
        false
      end
    end

    sig { void }
    def verify_new_tier_purchasable
      unless new_tier.available_for_purchase?
        raise ForbiddenError.new("Could not update sponsorship: chosen tier is not available")
      end
    end

    sig { void }
    def verify_sponsorship_unlocked
      raise UnprocessableError.new("Could not update sponsorship while it is processing") if sponsorship.locked?
    end

    sig { void }
    def verify_new_tier_has_same_frequency
      unless new_tier.frequency == previous_tier.frequency
        old_frequency = previous_tier.frequency_adjective
        new_frequency = new_tier.frequency_adjective
        raise UnprocessableError.new("Cannot switch from #{old_frequency} to #{new_frequency}")
      end
    end

    sig { void }
    def verify_invoiced_customer_balance
      return unless sponsor.sponsors_invoiced?

      price = new_tier.price(sponsor: sponsor, prorated: true)
      unless sponsor.sufficient_invoiced_sponsor_balance?(price)
        raise UnprocessableError.new("This amount exceeds what is in your balance. Contact support to add more funds.")
      end
    end

    sig { void }
    def verify_no_pending_cancellation
      if pending_tier_change&.cancellation?
        raise UnprocessableError.new("Could not update sponsorship tier: this sponsorship is pending cancellation")
      end
    end

    sig { void }
    def verify_no_pending_downgrade
      if pending_tier_change.present? && !T.must(pending_tier_change).cancellation?
        raise UnprocessableError.new("Could not update sponsorship tier: this sponsorship has a pending tier change")
      end
    end

    sig { returns(T.nilable(Billing::PendingSubscriptionItemChange)) }
    memoize def pending_tier_change
      sponsorship.pending_subscription_item_change
    end

    sig { returns(SponsorsTier) }
    attr_reader :new_tier

    sig { returns(T.any(User, Organization)) }
    attr_reader :sponsor

    sig { returns(T.any(User, Organization)) }
    attr_reader :sponsorable

    sig { returns(SponsorsTier) }
    attr_reader :previous_tier

    sig { returns(T.nilable(Billing::SubscriptionItem)) }
    attr_reader :old_subscription_item

    sig { returns T.nilable(Date) }
    attr_reader :active_on
  end
end
