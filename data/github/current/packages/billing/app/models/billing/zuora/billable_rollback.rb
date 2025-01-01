# typed: strict
# frozen_string_literal: true

class Billing::Zuora::BillableRollback

  sig { params(plan_subscription: Billing::PlanSubscription, error_message: String).void }
  def self.perform(plan_subscription, error_message)
    new(plan_subscription, error_message).perform
  end

  sig { returns(String) }
  attr_reader :error_message

  sig { returns(T::Boolean) }
  attr_reader :reset_marketplace_items

  sig { returns(::Billing::PlanSubscription) }
  attr_reader :plan_subscription

  delegate \
    :plan_duration,
    :subscription_items,
    :user,
    :zuora_subscription,
    to: :plan_subscription

  delegate \
    :active_rate_plans,
    to: :zuora_subscription,
    allow_nil: true

  sig { params(plan_subscription: Billing::PlanSubscription, error_message: String).void }
  def initialize(plan_subscription, error_message)
    @error_message = error_message
    @plan_subscription = plan_subscription
    @reset_marketplace_items = T.let(false, T::Boolean)
    @cancelled_sponsorships = T.let(false, T::Boolean)
  end

  sig { void }
  def perform
    GitHub.instrument("billing.billable_rollback", user: user, error: error_message)

    non_product_billable_subscription_items.each do |item|
      rate_plan = rate_plan_for(item)

      # If the Zuora subscription does not show the item as active, cancel it; otherwise
      # reset the item to its previous state (eg. before the attempted upgrade).
      #
      # One-time sponsorships are special cases. We support multiple one-time sponsorships,
      # and should always cancel the subscription item even though a rate plan may be active
      # from a past one-time sponsorship.
      if rate_plan.nil? || item.one_time_sponsorship?
        cancel_item(item)
      else
        reset_item(item, rate_plan)
      end
    end

    user.set_sponsorship_rollback_notification if @cancelled_sponsorships && user&.user?
    send_failure_notification if reset_marketplace_items
  end

  private

  sig { returns(T::Array[Billing::SubscriptionItem]) }
  def non_product_billable_subscription_items
    subscription_items.without_product_uuid_type.includes(:subscribable).to_a.select(&:billable?)
  end

  # Public: get the list of rate plans for billable (Sponsors or Marketplace) items
  # that are currently active in the Zuora subscription.
  sig { returns(T::Array[::Billing::Zuora::RatePlan]) }
  def billable_rate_plans
    Array(active_rate_plans).select do |rate_plan|
      billable_product_rate_plan_ids.include? rate_plan[:productRatePlanId]
    end
  end

  # Public: get the list of Zuora product rate plan IDs for billable (Sponsors or Marketplace)
  # items that are currently active in the Zuora subscription.
  sig { returns(T::Array[String]) }
  def billable_product_rate_plan_ids
    @_billable_product_rate_plan_ids ||= T.let(
      begin
        product_rate_plan_ids = Array(active_rate_plans).map { |rate_plan| rate_plan[:productRatePlanId] }
        Billing::ProductUUID
          .billable
          .for_zuora_product_rate_plan(product_rate_plan_ids)
          .pluck(:zuora_product_rate_plan_id)
      end, T.nilable(T::Array[String])
    )
  end

  # Public: get the rate plan from the list of subscribed rate plans on the current Zuora
  # subscription if one exists.
  #
  # item - a Billing::SubscriptionItem with a billable (Sponsors or Marketplace) subscribable
  sig { params(item: Billing::SubscriptionItem).returns(T.nilable(::Billing::Zuora::RatePlan)) }
  def rate_plan_for(item)
    rate_plan_ids_for_item = []

    subscribable = item.subscribable

    # SponsorsTier subscribables may have a billing cycle that overrides the subscriber's
    # plan duration.
    billing_cycle = subscribable.billing_cycle || plan_duration

    # Marketplace::ListingPlan subscribables will have their own rate plan,
    # and SponsorsTier subscribables may have their own rate plan.
    if subscribable_product_uuid = subscribable.product_uuid(billing_cycle)
      rate_plan_ids_for_item << subscribable_product_uuid.zuora_product_rate_plan_id
    end

    # SponsorsTier subscribables will have a rate plan for their listing.
    if listing_rate_plan_id = subscribable.listing_product_rate_plan_id(cycle: billing_cycle)
      rate_plan_ids_for_item << listing_rate_plan_id
    end

    billable_rate_plans.detect do |rate_plan|
      rate_plan[:productRatePlanId].in?(rate_plan_ids_for_item)
    end
  end

  sig { params(item: Billing::SubscriptionItem).void }
  def cancel_item(item)
    previous_quantity = item.quantity
    item.update_column(:quantity, 0)

    prefix = item.subscribable_SponsorsTier? ? "sponsorship" : "marketplace_purchase"
    GitHub.dogstats.increment("billing.billable_rollback",
      tags: ["action:cancel", "subscribable_type:#{item.subscribable_type}"]
    )
    GitHub.instrument "#{prefix}.cancelled",
      subscription_item_id: item.id,
      sender_id: item.managing_entity&.id,
      previous_quantity: previous_quantity,
      previous_subscribable_id: item.subscribable.id,
      previous_subscribable_type: item.subscribable.class.name
    @reset_marketplace_items = true
    @cancelled_sponsorships = true if item.subscribable_SponsorsTier?

    if item.subscribable_SponsorsTier?
      sponsor = item.managing_entity
      sponsorable = item.sponsorable
      sponsorship = Sponsorship.find_by(sponsor: sponsor, sponsorable: sponsorable)
      return unless sponsorship
      return unless sponsorship.tier == item.subscribable

      if sponsorship.update_column(:active, false)
        sponsorship.instrument_cancel_request(reason: :BILLABLE_ROLLBACK, force: true, actor: sponsor)
        sponsorship.instrument_cancel(actor: sponsor)
      end
    end
  end

  sig { params(item: Billing::SubscriptionItem, rate_plan: ::Billing::Zuora::RatePlan).void }
  def reset_item(item, rate_plan)
    previous_quantity = item.quantity
    quantity = quantity_for_rate_plan(rate_plan)
    return if quantity == previous_quantity

    item.update_column(:quantity, quantity)
    prefix = item.subscribable_SponsorsTier? ? "sponsorship" : "marketplace_purchase"
    GitHub.dogstats.increment("billing.billable_rollback",
      tags: ["action:reset", "subscribable_type:#{item.subscribable_type}"]
    )
    GitHub.instrument "#{prefix}.changed",
      subscription_item_id: item.id,
      sender_id: item.managing_entity&.id,
      previous_quantity: previous_quantity,
      previous_subscribable_id: item.subscribable.id,
      previous_subscribable_type: item.subscribable.class.name
    @reset_marketplace_items = true
  end

  sig { params(rate_plan: ::Billing::Zuora::RatePlan).returns(Integer) }
  def quantity_for_rate_plan(rate_plan)
    quantity = rate_plan[:ratePlanCharges].to_a.map { |charge| charge[:quantity].to_i }.max
    [quantity.to_i, 1].max
  end

  sig { void }
  def send_failure_notification
    Billing::PlanSubscription::SendFailureNotification.perform \
      plan_subscription,
      marketplace: true,
      message: error_message
  end
end
