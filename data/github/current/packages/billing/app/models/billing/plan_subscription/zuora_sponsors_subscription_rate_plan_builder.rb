# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::ZuoraSponsorsSubscriptionRatePlanBuilder
  include GitHub::Memoizer
  include Billing::PlanSubscription::ZuoraSubscriptionParams::ISubscribeAmendRatePlanBuilder

  sig { params(plan_subscription: Billing::PlanSubscription).void }
  def initialize(plan_subscription)
    @plan_subscription = plan_subscription
  end

  sig { override.returns(T::Array[Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam]) }
  memoize def rate_plans
    subscription_items.filter_map do |subscription_item|
      subscribe_amend_rate_plan_for(subscription_item)
    end
  end

  sig { override.returns(T::Hash[String, T.nilable(String)]) }
  memoize def contract_dates_by_rate_plan_id
    subscription_items.each_with_object({}) do |subscription_item, contract_dates|
      tier = subscription_item.subscribable
      listing = tier.sponsors_listing
      billing_cycle = tier.billing_cycle || plan_subscription.plan_duration
      listing_rate_plan_id = listing.zuora_rate_plan_id(billing_cycle: billing_cycle)
      contract_date = sponsors_contract_date_for(subscription_item)

      contract_dates[listing_rate_plan_id] = contract_date
    end
  end

  sig { override.returns(T::Boolean) }
  def non_github_product_rate_plans?
    # This is used by ZuoraSubscriptionParams to determine whether collect invoice should be set to true
    # Reason this returns true is because technically sponsors purpose plan subscriptions are all non-GitHub
    # However, the collect invoice flag is set to false early if the customer's Zuora acccount is sponsors purpose.
    # TODO: confirm whether a general purpose account can have a sponsors purpose plan subscription. If so,
    # we could return false here
    true
  end

  private

  sig { returns(T::Array[Billing::SubscriptionItem]) }
  memoize def subscription_items
    items = plan_subscription.active_subscription_items
      .for_sponsors_tiers
      .includes(:sponsorship, subscribable: :sponsors_list)
      .select(&:billable?)
    tiers = items.filter_map(&:subscribable)
    listings = tiers.map(&:sponsors_listing)
    billing_cycles = ([plan_subscription.plan_duration] + tiers.filter_map(&:billing_cycle)).uniq
    billing_cycles.each do |billing_cycle|
      # #product_uuid used by SponsorsListing#zuora_rate_plan_id in #sponsors_rate_plan_for
      # and SponsorsListing#zuora_rate_plan_charge_ids in #sponsors_overrides_for:
      GitHub::PrefillAssociations.prefill_batch_method(listings, :product_uuid, billing_cycle)
    end

    items
  end

  # Private: Get the contract date for a sponsorship.
  #
  # We care about the contract date if the user intended to skip proration the first time.
  # In that case, we backdate the sponsorship so the full amount is charged.
  #
  # We also care about the contract date for a one-time payment.
  #
  # item - a Billing::SubscriptionItem with subscribable_type="SponsorsTier"
  #
  # Otherwise, we return `nil` and allow the rest of the code to set the correct contract date.
  sig { params(item: Billing::SubscriptionItem).returns(T.nilable(String)) }
  def sponsors_contract_date_for(item)
    sponsorship = item.sponsorship
    return unless sponsorship&.skip_proration?

    tier = item.subscribable
    return unless tier.recurring?
    user = plan_subscription.user

    return unless user&.can_skip_sponsorship_proration?

    bill_cycle_day = user.customer_bill_cycle_day_for_sponsorships.to_i
    contract_date = GitHub::Billing.today

    if bill_cycle_day > contract_date.day && contract_date < contract_date.end_of_month
      contract_date = contract_date - 1.month
    end

    bill_cycle_day = [contract_date.end_of_month.day, bill_cycle_day].min

    backdated_date = contract_date.change(day: bill_cycle_day)
    # Zuora doesn't support backdating beyond the subscription effective date
    [backdated_date, plan_subscription.zuora_subscription&.contract_effective_date].compact.max.to_s
  end

  # Returns a Subscribe/Amend structure for rate plans
  sig do
    params(subscription_item: Billing::SubscriptionItem)
      .returns(T.nilable(Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam))
  end
  def subscribe_amend_rate_plan_for(subscription_item)
    tier = T.let(subscription_item.subscribable, T.nilable(T.any(Billing::ProductUUID, Billing::Types::Subscribable)))
    return unless tier.is_a?(SponsorsTier)

    listing = tier.sponsors_listing
    return unless listing

    billing_cycle = T.let(tier.billing_cycle || plan_subscription.plan_duration, T.any(String, Symbol))

    product_rate_plan_id = listing.zuora_rate_plan_id(billing_cycle: billing_cycle)
    unless product_rate_plan_id
      Failbot.push("gh.billing_cycle": billing_cycle, "gh.sponsors_listing.id": listing.id)
      raise Billing::PlanSubscription::ZuoraSubscriptionParams::MissingZuoraRatePlanChargeIdsError
    end

    subscribe_to_rate_plan = ::Billing::Zuora::OrderAction::SubscribeToRatePlan.new(product_rate_plan_id: product_rate_plan_id)
    subscribe_to_rate_plan.charge_overrides = sponsors_overrides_for(
      subscription_item,
      listing: listing,
      tier: tier,
      billing_cycle: billing_cycle,
    )

    subscribe_to_rate_plan.to_subscribe_amend_format
  end

  # Internal: An array of hashes to override the price on a specific
  # Sponsors Zuora product rate plan charge, which has a base price of $1 USD.
  #
  # - For the flat charge, the price will be the tier's price in dollars.
  #   - For one-time sponsorships, this always uses the monthly price.
  #   - For recurring sponsorships, either the monthly or yearly price is used, based on the
  #     user's plan duration.
  # - For the fee charge, the price will need to be determined when we're ready to add fees.
  #
  # item - A Billing::SubscriptionItem tied to a SponsorsTier.
  # listing - the SponsorsListing that `tier` is for
  # tier - the SponsorsTier tied to `item`
  # billing_cycle - the billing cycle for the sponsorship (e.g. "month", "year", "one_time")
  sig do
    params(
      item: Billing::SubscriptionItem,
      listing: SponsorsListing,
      tier: SponsorsTier,
      billing_cycle: T.any(String, Symbol),
    ).returns(T::Array[Billing::Zuora::OrderAction::ChargeOverride])
  end
  def sponsors_overrides_for(item, listing:, tier:, billing_cycle:)
    charge_ids = listing.zuora_rate_plan_charge_ids(billing_cycle: billing_cycle)
    unless charge_ids
      Failbot.push("gh.billing_cycle": billing_cycle, "gh.sponsors_listing.id": listing.id)
      raise Billing::PlanSubscription::ZuoraSubscriptionParams::MissingZuoraRatePlanChargeIdsError
    end
    flat_price = if tier.one_time?
      tier.to_money
    else
      tier.base_price(duration: billing_cycle)
    end

    tracking_attributes = {
      Billing::Subscribable::ZUORA_TRACKING_FIELD.to_sym => tier.zuora_tracking_id,
    }

    # Enterprise accounts require tracking the org related to the subscription item so we can handle multiple
    # member orgs each sponsoring the same maintainer. The subscription item holds the org information.
    if item.account&.business?
      tracking_attributes.merge!({ Billing::Zuora::RatePlanCharge::SUBSCRIPTION_ITEM_ID_FIELD.to_sym => item.id.to_s })
    end

    overrides = [
      ::Billing::Zuora::OrderAction::ChargeOverride.new(
        product_rate_plan_charge_id: charge_ids[:flat],
        pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_recurring_flat_fee(list_price: flat_price.to_f),
        custom_fields: tracking_attributes,
      )
    ]

    if charge_ids[:fee].present?
      overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
        product_rate_plan_charge_id: charge_ids[:fee],
        pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_recurring_flat_fee(list_price: item.sponsors_fee(flat_price).to_f),
        custom_fields: tracking_attributes,
      )
    end

    overrides
  end

  sig { returns(Billing::PlanSubscription) }
  attr_reader :plan_subscription
end
