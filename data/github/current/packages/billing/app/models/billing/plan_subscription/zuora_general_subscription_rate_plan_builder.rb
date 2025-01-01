# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::ZuoraGeneralSubscriptionRatePlanBuilder
  include GitHub::Memoizer
  include Billing::PlanSubscription::ZuoraSubscriptionParams::ISubscribeAmendRatePlanBuilder

  sig { params(plan_subscription: Billing::PlanSubscription).void }
  def initialize(plan_subscription)
    @plan_subscription = plan_subscription
  end

  # Public: Generates an array of product details for a given user, which includes their GitHub and
  # Marketplace purchases
  sig { override.returns(T::Array[Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam]) }
  memoize def rate_plans
    (github_rate_plans + marketplace_rate_plans).compact
  end

  sig { override.returns(T::Hash[String, T.nilable(String)]) }
  memoize def contract_dates_by_rate_plan_id
    {}
  end

  sig { override.returns(T::Boolean) }
  def non_github_product_rate_plans?
    (rate_plans - github_rate_plans).present?
  end

  private

  sig { returns(Billing::PlanSubscription) }
  attr_reader :plan_subscription

  sig { returns(GitHub::Plan) }
  def plan
    # TODO: remove and delegate once plan has been typed in User billing dependency
    plan_subscription.plan
  end

  sig { returns(T::Array[T.nilable(Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam)]) }
  memoize def github_rate_plans
    [
      github_rate_plan,
      github_lfs_plan,
      github_coupon,
    ] + metered_usage_rate_plans + product_uuid_subscriptions_rate_plans
  end

  sig { returns(T.nilable(Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam)) }
  def github_rate_plan
    return if plan.cost.zero? || plan_subscription.on_free_trial?
    billable_entity = plan_subscription.billable_entity
    return unless billable_entity&.eligible_for_nonmetered_github_plan?
    product_rate_plan_id = plan.zuora_id(cycle: plan_subscription.plan_duration)
    unless product_rate_plan_id
      Failbot.push("gh.plan_duration": plan_subscription.plan_duration, "gh.plan": plan.to_s)
      raise Billing::PlanSubscription::ZuoraSubscriptionParams::MissingZuoraRatePlanChargeIdsError
    end

    zuora_charge_ids = plan.zuora_charge_ids(cycle: plan_subscription.plan_duration)
    unless zuora_charge_ids
      Failbot.push("gh.plan_duration": plan_subscription.plan_duration, "gh.plan": plan.to_s)
      raise Billing::PlanSubscription::ZuoraSubscriptionParams::MissingZuoraRatePlanChargeIdsError
    end

    subscribe_to_rate_plan = ::Billing::Zuora::OrderAction::SubscribeToRatePlan.new(product_rate_plan_id: product_rate_plan_id)

    if plan.per_seat?
      current_seats = plan_subscription.seats
      business_plan_assumed_minimum_seats = Billing::PlanSubscription::ZuoraSubscriptionParams::BUSINESS_PLAN_ASSUMED_MINIMUM

      if plan.business?
        # Base charge quantity override
        quantity = current_seats >= business_plan_assumed_minimum_seats ? business_plan_assumed_minimum_seats : current_seats
        subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
          product_rate_plan_charge_id: T.must(zuora_charge_ids[:base_unit]),
          pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_recurring_per_unit(quantity: quantity)
        )
      end

      quantity =
        if plan.business?
          # Hack to assume organizations on team plan ALWAYS have 5 seats as the default quantity
          # see https://github.com/github/gitcoin/issues/4241
          [current_seats - business_plan_assumed_minimum_seats, 0].max
        elsif plan.base_cost?
          [current_seats - plan.base_units, 0].max
        else
          current_seats
        end
      subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
        product_rate_plan_charge_id: T.must(zuora_charge_ids[:unit]),
        pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_recurring_per_unit(quantity: quantity)
      )
    elsif plan_subscription.apple_iap_subscription? && plan.pro?
      # pro does not support seats so use :flat
      subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
        product_rate_plan_charge_id: T.must(zuora_charge_ids[:flat]),
        pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_recurring_flat_fee(list_price: 0.0)
      )
    end

    subscribe_to_rate_plan.to_subscribe_amend_format
  end

  sig { returns(T.nilable(Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam)) }
  def github_lfs_plan
    return unless plan_subscription.data_packs > 0

    product_rate_plan_id = Asset::Status.zuora_id(cycle: plan_subscription.plan_duration)
    subscribe_to_rate_plan = ::Billing::Zuora::OrderAction::SubscribeToRatePlan.new(product_rate_plan_id: product_rate_plan_id)
    subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
      product_rate_plan_charge_id: T.must(Asset::Status.zuora_charge_ids(cycle: plan_subscription.plan_duration)[:unit]),
      pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_recurring_per_unit(quantity: plan_subscription.data_packs)
    )

    subscribe_to_rate_plan.to_subscribe_amend_format
  end

  sig { returns(T.nilable(Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam)) }
  def github_coupon
    return unless coupon = plan_subscription.coupon
    discount_charge_override_type = plan_subscription.coupon.percentage? ? :discount_percentage : :discount_amount

    product_rate_plan_id = coupon.zuora_id(cycle: plan_subscription.plan_duration)
    subscribe_to_rate_plan = ::Billing::Zuora::OrderAction::SubscribeToRatePlan.new(product_rate_plan_id: product_rate_plan_id)
    subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
      product_rate_plan_charge_id: coupon.zuora_charge_ids(cycle: plan_subscription.plan_duration)[coupon.zuora_charge_type],
      pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_discount("#{discount_charge_override_type}": plan_subscription.coupon_amount)
    )

    subscribe_to_rate_plan.to_subscribe_amend_format
  end

  sig { returns(T::Array[Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam]) }
  memoize def metered_usage_rate_plans
    # TODO: once entitlments are moved out of Zuora, we should be able to stop sending chargeOverrides
    # and also stop checking for plan elegibility here
    product_type_eligibility = {
      "github.actions": plan.actions_eligible?,
      "github.codespaces": plan.codespaces_eligible?,
      "github.copilot": plan.copilot_for_biz_eligible?,
      "github.package_registry": plan.package_registry_eligible?,
      "github.shared_storage": plan.shared_storage_eligible?,
    }

    metered_uuids = Billing::ProductUUID.metered.reject { |uuid| product_type_eligibility[uuid.product_type.to_sym] == false }

    metered_uuids.map do |uuid|

      subscribe_to_rate_plan = ::Billing::Zuora::OrderAction::SubscribeToRatePlan.new(product_rate_plan_id: uuid.zuora_product_rate_plan_id)

      # Temporary method to get chargeOverrides for a metered ProductUUID. This will not be
      # necessary after migrating entitlements from Zuora
      if uuid.product_type == ::Billing::Actions::ZuoraProduct.product_type &&
        uuid.product_key == ::Billing::Actions::ZuoraProduct.private_visibility_rate_plan_charge.name

        subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
          product_rate_plan_charge_id: uuid.zuora_product_rate_plan_charge_ids.values.first,
          pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_usage_overage(
            included_units: plan.actions_included_private_minutes,
          )
        )
      elsif uuid.product_type == ::Billing::PackageRegistry::ZuoraProduct.product_type &&
        uuid.product_key == ::Billing::PackageRegistry::ZuoraProduct.product_key

        subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
          product_rate_plan_charge_id: uuid.zuora_product_rate_plan_charge_ids[:bandwidth],
          pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_usage_overage(
            included_units: plan.package_registry_included_bandwidth,
          )
        )
      elsif uuid.product_type == ::Billing::SharedStorage::ZuoraProduct.product_type &&
        uuid.product_key == ::Billing::SharedStorage::ZuoraProduct.product_key
        calculator = ::Billing::MeteredBilling::HourlyRateCalculator.new

        subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
          product_rate_plan_charge_id: uuid.zuora_product_rate_plan_charge_ids[:usage],
          pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_usage_overage(
            included_units: calculator.hourly_rate_for(units_per_month: plan.shared_storage_included_megabytes).round,
          )
        )
      end

      subscribe_to_rate_plan.to_subscribe_amend_format
    end
  end

  sig { returns(T::Array[Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam]) }
  def product_uuid_subscriptions_rate_plans
    product_sub_items = plan_subscription.active_subscription_items.with_product_uuid_type.includes(:subscribable)
    product_sub_items.select(&:billable?).map do |item|

      subscribe_to_rate_plan = ::Billing::Zuora::OrderAction::SubscribeToRatePlan.new(product_rate_plan_id: item.subscribable.zuora_product_rate_plan_id)

      if item.in_app_purchase?
        # Right now the only two offered IAP products are Copilot for Individuals monthly plans and Pro monthly plans.
        # Pro billing is done separately on the plan_subscription model so the only SubscriptionItem we need to handle
        # for IAP is the Copilot for Individuals monthly plan.
        #
        # This specific override works in this exact case: Copilot for Individuals monthly plan but might need to be
        # updated to account for other IAP products in the future.
        subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
          product_rate_plan_charge_id: item.subscribable.zuora_product_rate_plan_charge_ids[:flat],
          pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_recurring_flat_fee(list_price: 0.0)
        )
      elsif item.subscribable.per_unit?
        subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
          product_rate_plan_charge_id: item.subscribable.zuora_product_rate_plan_charge_ids[:unit],
          pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_recurring_per_unit(quantity: item.quantity)
        )
      elsif (charge = item.subscribable.charges.detect { |charge| charge.type == "flat" }) && !charge.prorate
        GitHub.dogstats.increment("billing.plan_subscription.product_uuid_override.no_prorate", tags: ["charge_name:#{charge.name}"])
        GitHub.logger.info(
          "code.namespace": self.class.name,
          "code.function": "product_uuid_overrides_for",
          "gh.billing.billable_entity.id": item.account&.id,
          "gh.billing.billable_entity.type": item.account&.class&.name,
          "gh.billing.billable_entity.login": item.account&.display_login,
          "gh.billing.product_uuid.charge.name": charge.name,
          "gh.billing.product_uuid.charge.type": charge.type,
          "gh.billing.product_uuid.charge.prorate": charge.prorate,
          "gh.billing.product_uuid.charge.zuora_product_rate_plan_charge_id": charge.zuora_product_rate_plan_charge_id,
          "gh.billing.subscription_item.id": item.id,
        )

        subscribe_to_rate_plan.charge_overrides << ::Billing::Zuora::OrderAction::ChargeOverride.new(
          product_rate_plan_charge_id: charge.zuora_product_rate_plan_charge_id,
          billing: ::Billing::Zuora::OrderAction::ChargeOverride::BillingParams.new(
            bill_cycle_type: "ChargeTriggerDay",
            billing_period_alignment: "AlignToCharge",
          )
        )
      end

      subscribe_to_rate_plan.to_subscribe_amend_format
    end
  end

  sig { returns(T::Array[Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam]) }
  memoize def marketplace_rate_plans
    marketplace_sub_items = plan_subscription.active_subscription_items.with_marketplace_listing_plans_type.includes(:subscribable)
    marketplace_sub_items.select(&:billable?).map do |item|
      product_rate_plan_id = item.subscribable.zuora_id(cycle: plan_subscription.plan_duration)
      unless product_rate_plan_id
        Failbot.push("gh.plan_duration": plan_subscription.plan_duration, "gh.marketplace_listing_plan.id": item.subscribable.id)
        raise Billing::PlanSubscription::ZuoraSubscriptionParams::MissingZuoraRatePlanChargeIdsError
      end

      subscribe_to_rate_plan = ::Billing::Zuora::OrderAction::SubscribeToRatePlan.new(product_rate_plan_id: product_rate_plan_id)

      listing_plan = T.let(item.subscribable, T.nilable(T.any(Billing::ProductUUID, Billing::Types::Subscribable)))
      if listing_plan.is_a?(Marketplace::ListingPlan)
        zuora_charge_ids = listing_plan.zuora_charge_ids(cycle: plan_subscription.plan_duration)
        unless zuora_charge_ids
          Failbot.push("gh.plan_duration": plan_subscription.plan_duration, "gh.marketplace_listing_plan.id": listing_plan.id)
          raise Billing::PlanSubscription::ZuoraSubscriptionParams::MissingZuoraRatePlanChargeIdsError
        end

        override =
          if listing_plan.per_unit?
            ::Billing::Zuora::OrderAction::ChargeOverride.new(
              product_rate_plan_charge_id: zuora_charge_ids[:unit],
              pricing: ::Billing::Zuora::OrderAction::ChargeOverride::Pricing.with_recurring_per_unit(quantity: item.quantity)
            )
          else
            ::Billing::Zuora::OrderAction::ChargeOverride.new(product_rate_plan_charge_id: zuora_charge_ids[:flat])
          end

        override.custom_fields = { Billing::Zuora::RatePlanCharge::SUBSCRIPTION_ITEM_ID_FIELD.to_sym => item.id.to_s }

        subscribe_to_rate_plan.charge_overrides << override
      end

      subscribe_to_rate_plan.to_subscribe_amend_format
    end
  end
end
