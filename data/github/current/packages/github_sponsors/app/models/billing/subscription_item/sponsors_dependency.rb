# typed: true
# frozen_string_literal: true

module Billing::SubscriptionItem::SponsorsDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  extend T::Sig

  requires_ancestor { Billing::SubscriptionItem }

  # In order to prevent multiple payments of the same subscription item with a one-time subscribable,
  # they are no longer sent for payment after they're considered stale.
  ONE_TIME_STALE_THRESHOLD = T.let(1.hour, ActiveSupport::Duration)

  included do
    T.bind(self, T.class_of(Billing::SubscriptionItem))

    has_one :sponsorship, dependent: :destroy

    scope :for_sponsors_tiers, -> { where(subscribable_type: SponsorsTier.name) }
    scope :for_sponsors_listing, -> (listing_id, frequency: nil) {
      sponsors_tiers = SponsorsTier.for_listing(listing_id)
      sponsors_tiers = sponsors_tiers.where(frequency: frequency) if frequency
      for_sponsors_tiers.where(subscribable_id: sponsors_tiers.pluck(:id))
    }

    scope :at_sponsors_tier_price, ->(monthly_price_in_cents, listing_id:) do
      tiers_at_same_price = SponsorsTier
        .for_listing(listing_id)
        .where(monthly_price_in_cents: monthly_price_in_cents)
        .pluck(:id)
      for_sponsors_tiers.where(subscribable_id: tiers_at_same_price)
    end

    validate :tier_not_owned_by_sponsor, on: :create, if: :subscribable_SponsorsTier?
  end

  class_methods do
    extend T::Sig

    # Public: Look up a subscription item for the specified Sponsors tier and plan subscription.
    #
    # tier_id - SponsorsTier ID
    # plan_subscription - a Billing::PlanSubscription or its ID
    sig do
      params(
        tier_id: Integer,
        plan_subscription: Billing::PlanSubscription,
      ).returns(T.nilable(Billing::SubscriptionItem))
    end
    def for_sponsors_one_time_payment(tier_id, plan_subscription)
      T.bind(self, T.class_of(Billing::SubscriptionItem))
      for_sponsors_tiers.find_by(subscribable_id: tier_id, plan_subscription_id: plan_subscription)
    end
  end

  sig { returns(T::Boolean) }
  def stale_one_time_sponsorship?
    return false if updated_at.nil?

    # Not billable if the subscription item hasn't been updated recently.
    T.must(updated_at) <= ONE_TIME_STALE_THRESHOLD.ago && one_time_sponsorship?
  end

  # Public: Determines the fee for a sponsorship, if any.
  #
  # flat_price - the flat price to add the fee on top of as Billing::Money
  sig { params(flat_price: Billing::Money).returns(Billing::Money) }
  def sponsors_fee(flat_price)
    return Billing::Money.zero unless subscribable_SponsorsTier?

    billable_entity = account
    return Billing::Money.zero if !billable_entity || billable_entity.user? # we never charge individuals fees
    return Billing::Money.zero unless customer&.payment_method&.credit_card? # we only charge fees for CC orgs

    Sponsorship.fee_for_credit_card_org_sponsorship_at(flat_price)
  end

  # Public: Check if this subscription item is paid for via a sponsorship-specific plan subscription. This does not
  # necessarily mean the sponsor is an invoiced Premium Sponsor; see https://github.com/github/sponsors/issues/4169.
  sig { returns T::Boolean }
  def sponsorship_specific_plan_subscription?
    !!plan_subscription&.sponsors_purpose?
  end

  # Public: Check if this subscription item is paid for via a sponsorship-specific Zuora account, implying
  # this is for an invoiced sponsor.
  sig { returns T::Boolean }
  def sponsorship_specific_customer?
    !!customer&.sponsors_purpose?
  end

  sig { returns T.nilable(Integer) }
  def sponsorship_id
    return @sponsorship_id if defined?(@sponsorship_id)
    @sponsorship_id = if subscribable_SponsorsTier?
      sponsorship&.id
    end
  end

  # Public: Check if this subscription item represents a one-time Sponsors payment.
  sig { returns T::Boolean }
  def one_time_sponsorship?
    return false unless subscribable_SponsorsTier? && subscribable
    subscribable.one_time?
  end

  # Public: Check if this subscription item represents a recurring Sponsors payment.
  sig { returns T::Boolean }
  def recurring_sponsorship?
    return false unless subscribable_SponsorsTier? && subscribable
    subscribable.recurring?
  end

  sig { returns T.nilable(Integer) }
  def sponsorable_id
    return unless subscribable_SponsorsTier?
    subscribable&.sponsorable_id
  end

  # Public: Get the user or organization being sponsored by this subscription item, if applicable.
  sig { returns T.nilable(GitHubSponsors::Types::Sponsorable) }
  def sponsorable
    async_sponsorable.sync
  end

  # Public: Determine if this subscription item was used to fund an organization via sponsorship.
  sig { returns T::Boolean }
  def sponsored_organization?
    return false unless subscribable_SponsorsTier?
    !!sponsorable&.organization?
  end

  # Public: Determine if this subscription item was used to fund an individual user via sponsorship.
  sig { returns T::Boolean }
  def sponsored_user?
    return false unless subscribable_SponsorsTier?
    !!sponsorable&.user?
  end

  sig { returns Promise[T.nilable(GitHubSponsors::Types::Sponsorable)] }
  def async_sponsorable
    if !subscribable_SponsorsTier?
      return Promise.resolve(T.let(nil, T.nilable(GitHubSponsors::Types::Sponsorable)))
    end
    async_subscribable.then do |sponsors_tier|
      sponsors_tier&.async_sponsorable
    end
  end

  sig { returns Promise[T::Array[SponsorsTier]] }
  def async_all_sponsors_tier_ids_for_listing
    return Promise.resolve(T.let([], T::Array[SponsorsTier])) unless subscribable_SponsorsTier?
    self.async_subscribable.then do |subscribable|
      SponsorsTier.for_listing(subscribable.sponsors_listing_id).pluck(:id)
    end
  end

  sig { returns T::Boolean }
  def pending_sponsorship_activation?
    return false unless subscribable_SponsorsTier?
    return false if active?
    pending_change = pending_subscription_item_change
    return false unless pending_change.present? && pending_change.quantity.positive?
    pending_change.subscribable_id == subscribable_id && pending_change.organization_id == organization_id
  end

  private

  sig { void }
  def tier_not_owned_by_sponsor
    return unless subscribable && user

    errors.add(:sponsor, "cannot sponsor themselves") if subscribable.sponsorable_id == user.id
  end
end
