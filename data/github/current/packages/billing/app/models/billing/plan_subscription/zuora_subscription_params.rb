# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::ZuoraSubscriptionParams
  include FeatureFlagHelper
  include GitHub::Memoizer
  include Scientist

  BUSINESS_PLAN_ASSUMED_MINIMUM = 5

  sig { returns Billing::PlanSubscription }
  attr_reader :plan_subscription

  sig { returns T.nilable(User) }
  attr_reader :user

  sig { returns T.nilable(::Billing::Types::Account) }
  attr_reader :billable_entity

  delegate \
    :active_subscription_items,
    :coupon,
    :coupon_amount,
    :customer,
    :data_packs,
    :on_free_trial?,
    :plan_duration,
    :plan_duration_in_months,
    :zuora_account_id,
    :zuora_account_number,
    :zuora_subscription,
    :zuora_subscription_number,
    to: :plan_subscription

  sig { returns(GitHub::Plan) }
  def plan
    # TODO: remove and delegate once plan has been typed in User billing dependency
    plan_subscription.plan
  end

  sig { returns T.nilable(Date) }
  def charged_through_date
    zuora_subscription&.charged_through_date
  end

  # plan_subscription - a Billing::PlanSubscription
  sig { params(plan_subscription: Billing::PlanSubscription).void }
  def initialize(plan_subscription:)
    @plan_subscription = plan_subscription
    @user = T.let(plan_subscription.user, T.nilable(User))
    @billable_entity = T.let(plan_subscription.billable_entity, T.nilable(::Billing::Types::Account))
    @pricing = T.let(Billing::Pricing.new(plan_subscription: plan_subscription), Billing::Pricing)
    @subscription_item_id_field = T.let(Billing::Zuora::RatePlanCharge::SUBSCRIPTION_ITEM_ID_FIELD.to_sym, Symbol)
    Failbot.push(
      "gh.user.id": @user&.id,
      "gh.plan_subscription.id": @plan_subscription.id,
      "gh.billable_entity.id": @billable_entity&.id,
      "gh.billable_entity.type": @billable_entity&.class&.name,
    )
  end

  CancelParams = T.type_alias do
    {
      cancellationPolicy: String,
      cancellationEffectiveDate: String,
      invoiceCollect: T::Boolean,
    }
  end

  RatePlanUpdate = T.type_alias do
    {
      contractEffectiveDate: String,
      ratePlanId: String,
      chargeUpdateDetails: T::Array[T::Hash[Symbol, T.untyped]],
    }
  end

  RatePlanAddition = T.type_alias do
    {
      productRatePlanId: String,
      contractEffectiveDate: String,
      chargeOverrides: T::Array[ChargeOverrideParams]
    }
  end

  RatePlanRemove = T.type_alias do
    {
      contractEffectiveDate: String,
      ratePlanId: String,
    }
  end

  SubscriptionRatePlanParam = T.type_alias do
    {
      productRatePlanId: String,
      chargeOverrides: T::Array[ChargeOverrideParams]
    }
  end

  ChargeOverrideParams = T.type_alias do
    T::Hash[Symbol, T.any(String, Billing::Types::Numeric)]
  end


  # Public: Generates the hash sent to Zuora to create the user's subscription, which includes the product
  # rate plans they're subscribing to, as well as the default processing options
  sig { returns T::Hash[Symbol, T.untyped] }
  def create_params
    params = {
      applyCreditBalance: apply_credit_balance?,
      accountKey: zuora_account_id,
      contractEffectiveDate: contract_effective_date,
      termType: "EVERGREEN",
      subscribeToRatePlans: rate_plans,
      runBilling: true,
      collect: collect_invoice_for_create_params?,
    }

    if plan_subscription.sponsors_purpose?
      params[:gatewayId] = GitHub.zuora_sponsors_payment_gateway_id
      params[:invoiceSeparately] = true
      params[:PaymentGateway__c] = Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2
    end

    params
  end

  # Public: Generates the hash sent to Zuora to update the user's subscription
  #
  # Handles prorated upgrades/downgrades by setting contractEffectiveDate on product changes
  sig { returns T::Hash[Symbol, T.untyped] }
  def update_params
    params = {
      applyCreditBalance: apply_credit_balance?,
      runBilling: true,
      collect: collect_invoice_for_update_params?,
      update: updates,
      remove: removals,
      add: additions,
    }

    if plan_subscription.sponsors_purpose?
      params[:gatewayId] = GitHub.zuora_sponsors_payment_gateway_id
    end

    params
  end

  # Public: Generates the hash sent to Zuora to cancel the user's subscription
  sig { returns(CancelParams) }
  def cancel_params
    {
      cancellationPolicy: "SpecificDate",
      cancellationEffectiveDate: charged_through_date.to_s,
      invoiceCollect: false,
    }
  end

  # Public: Generates an array of product details for a given user, which includes their GitHub and
  # Marketplace purchases, and Sponsorships
  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  memoize def rate_plans
    if plan_subscription.sponsors_purpose?
      sponsors_rate_plans
    else
      if sponsors_self_serve_enterprise_feature_enabled?
        (github_rate_plans + marketplace_rate_plans).compact
      else
        (github_rate_plans + billable_rate_plans).compact
      end
    end
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  def metered_usage_rate_plans
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
      {
        productRatePlanId: uuid.zuora_product_rate_plan_id,
        chargeOverrides: metered_usage_overrides_for(uuid),
      }
    end
  end

  sig { returns(T::Array[T.nilable(SubscriptionRatePlanParam)]) }
  memoize def github_rate_plans
    [
      github_rate_plan,
      github_lfs_plan,
      github_coupon,
    ] + metered_usage_rate_plans + product_uuid_subscriptions_rate_plans
  end

  private

  sig { returns Billing::Pricing }
  attr_reader :pricing

  sig { returns Symbol }
  attr_reader :subscription_item_id_field

  sig { returns(T.nilable(SubscriptionRatePlanParam)) }
  def github_rate_plan
    return if plan.cost.zero? || on_free_trial?
    billable_entity = self.billable_entity
    return unless billable_entity&.eligible_for_nonmetered_github_plan?
    product_rate_plan_id = plan.zuora_id(cycle: plan_duration)
    unless product_rate_plan_id
      Failbot.push("gh.plan_duration": plan_duration, "gh.plan": plan.to_s)
      raise MissingZuoraRatePlanChargeIdsError
    end

    {
      productRatePlanId: product_rate_plan_id,
      chargeOverrides: github_charge_overrides,
    }
  end

  # Should Zuora collect payment for the invoice immediately.
  # Payments are collected immediately if there are any Marketplace or
  # GitHub Sponsors items added or updated
  #
  # rate_plans - The Array of rate plans to check for non GitHub rate plans inclusion
  sig { params(rate_plans: T::Array[SubscriptionRatePlanParam]).returns(T::Boolean) }
  def collect_invoice?(rate_plans:)
    return false if customer&.requires_manual_transactions?

    # Sponsors-purpose customers lack an electronic payment method, we default to false
    return false if customer&.sponsors_purpose?
    (rate_plans - github_rate_plans).present?
  end

  sig { returns(T::Boolean) }
  def collect_invoice_for_create_params?
    if customer&.business.present? && !customer&.payment_method&.credit_card? && !customer&.payment_method&.paypal?
      return false
    end
    collect_invoice?(rate_plans: rate_plans)
  end

  sig { returns(T::Boolean) }
  memoize def collect_invoice_for_update_params?
    if plan_subscription.sponsors_purpose? && sponsors_skip_invoice_collection_for_update_enabled?
      return false
    end
    collect_invoice?(rate_plans: addition_rate_plans + updated_rate_plans)
  end

  sig { returns(T::Boolean) }
  def sponsors_skip_invoice_collection_for_update_enabled?
    return false unless billable_entity.present?

    T.must(billable_entity).feature_enabled?(:sponsors_skip_invoice_collection_for_update)
  end

  sig { returns(T::Array[RatePlanUpdate]) }
  memoize def updates
    updated_rate_plans.map do |updated_plan|
      found_rate_plan = if sponsors_self_serve_enterprise_feature_enabled?
        active_zuora_rate_plans.find do |active_rate_plan|
          active_rate_plan.matches_candidate?(updated_plan, org_id_by_sub_item_id_mapping)
        end
      else
        rate_plan_for_product_rate_plan_id(updated_plan[:productRatePlanId])
      end

      rate_plan = T.must(found_rate_plan)

      selected_overrides = updated_plan[:chargeOverrides].reject do |override|
        plan_annual_discount_overrides = self.plan_annual_discount_overrides
        next if override.blank? || !override.key?(:productRatePlanChargeId) || plan_annual_discount_overrides.blank?

        override[:productRatePlanChargeId] == plan_annual_discount_overrides[:productRatePlanChargeId]
      end
      charge_updates = selected_overrides.each do |override|
        charge = T.must(charge_for_charge_id(rate_plan, override.delete(:productRatePlanChargeId)))
        override[:ratePlanChargeId] = charge[:id]
      end
      {
        contractEffectiveDate: today,
        ratePlanId: rate_plan[:id],
        chargeUpdateDetails: charge_updates,
      }
    end
  end

  sig { returns(T::Array[RatePlanAddition]) }
  memoize def additions
    addition_rate_plans.map do |new_plan|
      rate_plan_id = new_plan[:productRatePlanId]
      contract_effective_date = sponsors_contract_dates_by_rate_plan_id[rate_plan_id] || today
      new_plan.merge(contractEffectiveDate: contract_effective_date)
    end
  end

  sig { returns(T::Array[RatePlanRemove]) }
  memoize def removals
    removals = removed_rate_plans.map do |removed_rate_plan|
      {
        contractEffectiveDate: today,
        ratePlanId: removed_rate_plan[:id],
      }
    end

    if coupon
      updated_discount_rate_plans.each do |plan|
        plan_id = plan[:productRatePlanId]
        if current_rate_plan_ids.include?(plan_id)
          rate_plan = T.must(rate_plan_for_product_rate_plan_id(plan_id))
          removals << {
            contractEffectiveDate: today,
            ratePlanId: rate_plan[:id]
          }
        end
      end
    end

    removals
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  memoize def updated_rate_plans
    plans = per_unit_rate_plans - discount_rate_plans

    plans.select do |rate_plan|
      if sponsors_self_serve_enterprise_feature_enabled?
        next if one_time_rate_plan?(rate_plan)
      else
        product_rate_plan_id = rate_plan[:productRatePlanId]
        subscription_item = sponsors_subscription_items_by_rate_plan_id[product_rate_plan_id]
        next if subscription_item&.one_time_sponsorship?
      end

      active_zuora_rate_plans.any? do |active_rate_plan|
        if sponsors_self_serve_enterprise_feature_enabled?
          next unless active_rate_plan.matches_candidate?(rate_plan, org_id_by_sub_item_id_mapping)
          has_updated_charge_details?(rate_plan, active_rate_plan)
        else
          same_rate_plan = active_rate_plan.product_rate_plan_id == rate_plan[:productRatePlanId]
          synced_subscription_item_id = active_rate_plan.subscription_item_id
          if synced_subscription_item_id.nil?
            same_subscription_item_charge = true
          else
            same_subscription_item_charge = rate_plan[:chargeOverrides].pick(subscription_item_id_field).to_i == synced_subscription_item_id
          end

          same_rate_plan && same_subscription_item_charge && has_updated_charge_details?(rate_plan, active_rate_plan)
        end
      end
    end
  end

  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  def removed_rate_plans
    rate_plan_count = Hash.new(0)
    rate_plans_to_remove = active_zuora_rate_plans.reject do |active_rate_plan|
      # Don't remove sponsors OTP rate plans
      next true if active_sponsors_otp_rate_plan_ids.include?(active_rate_plan.product_rate_plan_id)
      # Remove duplicate rate plans that have been added to Zuora
      unique_id = active_rate_plan.product_rate_plan_id + active_rate_plan.subscription_item_id.to_s
      rate_plan_count[unique_id] += 1
      if (count = rate_plan_count[unique_id]) > 1
        GitHub.dogstats.increment("billing.plan_subscription.duplicate_rate_plan",
          tags: ["product_name:#{active_rate_plan.product_name}", "count:#{count}"])
        GitHub.logger.info(
          "Found duplicate rate plan",
          "code.namespace" => self.class.name,
          "code.function" => "removed_rate_plans",
          "gh.billing.billable_entity.id" => billable_entity&.id,
          "gh.billing.billable_entity.type" => billable_entity.class,
          "gh.billing.zuora.subscription_number" => zuora_subscription_number,
          "gh.billing.zuora.rate_plan.id" => active_rate_plan[:id],
          "gh.billing.zuora.rate_plan.product_name" => active_rate_plan.product_name,
          "gh.billing.zuora.rate_plan.product_rate_plan_id" => active_rate_plan.product_rate_plan_id,
          "gh.billing.zuora.rate_plan.subscription_item_id" => active_rate_plan.subscription_item_id.to_s,
          "gh.billing.zuora.rate_plan.count" => count
        )
        next false if remove_duplicate_rate_plans_enabled?
      end
      # Remove rate plans in Zuora that aren't present locally
      rate_plans.any? do |local_rate_plan|
        if sponsors_self_serve_enterprise_feature_enabled?
          active_rate_plan.matches_candidate?(local_rate_plan, org_id_by_sub_item_id_mapping)
        else
          synced_product_rate_plan_id = active_rate_plan.product_rate_plan_id
          synced_subscription_item_id = active_rate_plan.subscription_item_id

          same_product_rate_plan = local_rate_plan[:productRatePlanId] == synced_product_rate_plan_id
          if synced_subscription_item_id.nil?
            same_subscription_item_charge = true
          else
            same_subscription_item_charge = local_rate_plan[:chargeOverrides].pick(subscription_item_id_field).to_i == synced_subscription_item_id
          end

          same_product_rate_plan && same_subscription_item_charge
        end
      end
    end

    rate_plans_to_remove
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  memoize def addition_rate_plans
    # Get a filtered list of rate plan hashes for adding to the user's subscription:
    plans = if sponsors_self_serve_enterprise_feature_enabled?
      rate_plans.reject { |candidate_rate_plan| existing_rate_plan?(candidate_rate_plan) }
    else
      rate_plans.reject { |plan| already_existing_stale_or_inactive_rate_plan?(plan) }
    end

    plans += updated_discount_rate_plans if coupon && updated_discount_rate_plans
    plans
  end

  # Private: Determine if a rate plan already exists on the Zuora subscription, or is both
  # stale and inactive on the Zuora subscription.
  #
  # plan - a Hash of details about a rate plan
  sig { params(plan: SubscriptionRatePlanParam).returns(T::Boolean) }
  def already_existing_stale_or_inactive_rate_plan?(plan)
    rate_plan_id = plan[:productRatePlanId]
    subscription_item = sponsors_subscription_items_by_rate_plan_id[rate_plan_id]

    if subscription_item&.one_time_sponsorship?
      max_active_effective_end_date = active_zuora_rate_plans
        .select { |rate_plan| rate_plan[:productRatePlanId] == rate_plan_id }
        .flat_map { |rate_plan| rate_plan.rate_plan_charges }
        .map { |charge| charge.effective_end_date }
        .compact
        .max
      return false if max_active_effective_end_date && GitHub::Billing.today.after?(max_active_effective_end_date)
    end

    if sponsors_self_serve_enterprise_feature_enabled?
      active_zuora_rate_plans.any? do |active_rate_plan|
        active_rate_plan.matches_candidate?(plan, org_id_by_sub_item_id_mapping)
      end
    else
      if subscription_item&.sponsorable
        active_zuora_rate_plan_ids.include?(rate_plan_id)
      else
        active_zuora_business_marketplace_plan_ids.any? do |active_plan_id, active_subscription_item_id|
          if active_plan_id == rate_plan_id
            if active_subscription_item_id.nil?
              true
            else
              active_subscription_item_id == plan[:chargeOverrides].pick(subscription_item_id_field).to_i
            end
          else
            false
          end
        end
      end
    end
  end

  # Private: Determine if a rate plan already exists on the Zuora subscription
  #
  # candidate_rate_plan - a Hash of details about a rate plan generated from GitHub data
  #
  # Returns a Boolean.
  sig { params(candidate_rate_plan: SubscriptionRatePlanParam).returns(T::Boolean) }
  def existing_rate_plan?(candidate_rate_plan)
    return duplicate_one_time_addition?(candidate_rate_plan) if one_time_rate_plan?(candidate_rate_plan)

    active_zuora_rate_plans.any? do |active_rate_plan|
      active_rate_plan.matches_candidate?(candidate_rate_plan, org_id_by_sub_item_id_mapping)
    end
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  memoize def discount_rate_plans
    rate_plans.select do |rate_plan|
      discount_ids.include?(rate_plan[:productRatePlanId])
    end
  end

  sig { returns T::Set[String] }
  memoize def discount_ids
    Set.new(Billing::ProductUUID.discounts.pluck(:zuora_product_rate_plan_id))
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  def per_unit_rate_plans
    rate_plans.select { |rate_plan| rate_plan[:chargeOverrides].any? }
  end

  sig do
    params(
      rate_plan: SubscriptionRatePlanParam,
      existing_rate_plan: Billing::Zuora::RatePlan
    ).returns(T::Boolean)
  end
  def has_updated_discount_charge_details?(rate_plan, existing_rate_plan)
    charge = rate_plan[:chargeOverrides].first
    existing_rate_plan.rate_plan_charges.any? do |existing_charge|
      existing_charge.product_rate_plan_charge_id == charge[:productRatePlanChargeId] &&
      discount_changed?(existing_charge, charge)
    end
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  memoize def updated_discount_rate_plans
    discount_rate_plans.select do |rate_plan|
      active_zuora_rate_plans.any? do |existing_rate_plan|
        existing_rate_plan[:productRatePlanId] == rate_plan[:productRatePlanId] &&
          has_updated_discount_charge_details?(rate_plan, existing_rate_plan)
      end
    end
  end

  sig do
    params(
      rate_plan: SubscriptionRatePlanParam,
      existing_rate_plan: Billing::Zuora::RatePlan
    ).returns(T::Boolean)
  end
  def has_updated_charge_details?(rate_plan, existing_rate_plan)
    rate_plan[:chargeOverrides].any? do |charge|
      existing_rate_plan.rate_plan_charges.present? &&
        existing_rate_plan.rate_plan_charges.any? do |existing_charge|
          existing_charge.product_rate_plan_charge_id == charge[:productRatePlanChargeId] &&
            (
              quantity_changed?(existing_charge, charge) ||
              included_units_changed?(existing_charge, charge) ||
              price_changed?(existing_charge, charge) ||
              subscribable_tracking_id_changed?(existing_charge, charge)
            )
        end
    end
  end

  sig { params(product_rate_plan_id: String).returns(T.nilable(Billing::Zuora::RatePlan)) }
  def rate_plan_for_product_rate_plan_id(product_rate_plan_id)
    active_zuora_rate_plans.detect do |existing_rate_plan|
      existing_rate_plan.product_rate_plan_id == product_rate_plan_id
    end
  end

  sig do
    params(
      rate_plan: Billing::Zuora::RatePlan,
      product_charge_id: String
    ).returns(T.nilable(Billing::Zuora::RatePlanCharge))
  end
  def charge_for_charge_id(rate_plan, product_charge_id)
    rate_plan.rate_plan_charges.detect do |charge|
      charge.product_rate_plan_charge_id == product_charge_id
    end
  end

  sig do
    params(
      existing_charge: Billing::Zuora::RatePlanCharge,
      charge: ChargeOverrideParams
    ).returns(T::Boolean)
  end
  def included_units_changed?(existing_charge, charge)
    existing_charge[:includedUnits].to_i != charge[:includedUnits].to_i
  end

  sig do
    params(
      existing_charge: Billing::Zuora::RatePlanCharge,
      charge: ChargeOverrideParams
    ).returns(T::Boolean)
  end
  def quantity_changed?(existing_charge, charge)
    return false unless charge.has_key?(:quantity)

    existing_charge[:quantity].to_i != charge[:quantity].to_i
  end

  sig do
    params(
      existing_charge: Billing::Zuora::RatePlanCharge,
      charge: ChargeOverrideParams
    ).returns(T::Boolean)
  end
  def discount_changed?(existing_charge, charge)
    return false unless coupon
    existing_charge[discount_charge_override_type] != charge[discount_charge_override_type]
  end

  # Private: check whether the price has changed between the existing Zuora subscription charge
  # and the expected GitHub charge.
  #
  # existing_charge - :ratePlanCharge on the existing Zuora subscription
  # charge          - :chargeOverride from an active GitHub plan
  #
  # The GitHub charge is a Billing::Money price in cents, and the Zuora charge is a price in
  # dollars.
  sig do
    params(
      existing_charge: Billing::Zuora::RatePlanCharge,
      charge: ChargeOverrideParams
    ).returns(T::Boolean)
  end
  def price_changed?(existing_charge, charge)
    return false unless charge.has_key?(:price)

    existing_price_in_cents = (existing_charge[:price] * 100).to_i
    Billing::Money.new(existing_price_in_cents) != charge[:price]
  end

  # Private: check whether the subscribable tracking ID has changed between the existing
  # Zuora subscription charge and the expected GitHub charge.
  #
  # existing_charge - :ratePlanCharge on the existing Zuora subscription
  # charge          - :chargeOverride from an active GitHub plan
  sig do
    params(
      existing_charge: Billing::Zuora::RatePlanCharge,
      charge: ChargeOverrideParams
    ).returns(T::Boolean)
  end
  def subscribable_tracking_id_changed?(existing_charge, charge)
    tracking_field = Billing::Subscribable::ZUORA_TRACKING_FIELD.to_sym

    existing_charge[tracking_field] != charge[tracking_field]
  end

  # Internal: An array of hashes to override the quantity on a specific
  # Marketplace Zuora product rate plan charge.
  #
  # item - A Billing::SubscriptionItem tied to a Marketplace::ListingPlan.
  sig do
    params(item: Billing::SubscriptionItem).returns(T.nilable(T::Array[T::Hash[Symbol, T.any(String, Integer)]]))
  end
  def marketplace_overrides_for(item)
    listing_plan = T.let(item.subscribable, T.nilable(T.any(Billing::ProductUUID, Billing::Types::Subscribable)))
    return unless listing_plan.is_a?(Marketplace::ListingPlan)

    zuora_charge_ids = listing_plan.zuora_charge_ids(cycle: plan_duration)
    unless zuora_charge_ids
      Failbot.push("gh.plan_duration": plan_duration, "gh.marketplace_listing_plan.id": listing_plan.id)
      raise MissingZuoraRatePlanChargeIdsError
    end

    overrides = { subscription_item_id_field => item.id.to_s }

    if listing_plan.per_unit?
      overrides.merge!(
        productRatePlanChargeId: zuora_charge_ids[:unit],
        quantity: item.quantity
      )
    else
      overrides[:productRatePlanChargeId] = zuora_charge_ids[:flat]
    end

    [overrides]
  end

  # Internal: An array of hashes to override the quantity on a specific
  # ProductUUID Zuora product rate plan charge.
  sig { params(item: Billing::SubscriptionItem).returns(T::Array[ChargeOverrideParams]) }
  def product_uuid_overrides_for(item)
    overrides = []

    if item.in_app_purchase?
      # Right now the only two offered IAP products are Copilot for Individuals monthly plans and Pro monthly plans.
      # Pro billing is done separately on the plan_subscription model so the only SubscriptionItem we need to handle
      # for IAP is the Copilot for Individuals monthly plan.
      #
      # This specific override works in this exact case: Copilot for Individuals monthly plan but might need to be
      # updated to account for other IAP products in the future.
      overrides << {
        productRatePlanChargeId: item.subscribable.zuora_product_rate_plan_charge_ids[:flat],
        price: 0
      }
    elsif item.subscribable.per_unit?
      overrides << {
        productRatePlanChargeId: item.subscribable.zuora_product_rate_plan_charge_ids[:unit],
        quantity: item.quantity,
      }
    elsif item.copilot_individual? && item.yearly?
      GitHub.dogstats.increment("billing.copilot_full_yearly_charge_enabled")
      GitHub::Logger.log(
        at: "billing.copilot_full_yearly_charge_enabled",
        item_id: item.id,
        account: T.cast(item.account, User).login
      )

      overrides << {
        productRatePlanChargeId: item.subscribable.zuora_product_rate_plan_charge_ids[:flat],
        billCycleType: "ChargeTriggerDay",
        billingPeriodAlignment: "AlignToCharge"
      }
    end

    overrides
  end

  class MissingZuoraRatePlanChargeIdsError < StandardError; end

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
  #
  # Returns an Array[Hash]
  sig do
    params(
      item: Billing::SubscriptionItem,
      listing: SponsorsListing,
      tier: SponsorsTier,
      billing_cycle: T.any(String, Symbol)
    ).returns(T::Array[T::Hash[Symbol, T.any(String, Billing::Money)]])
  end
  def sponsors_overrides_for(item, listing:, tier:, billing_cycle:)
    charge_ids = listing.zuora_rate_plan_charge_ids(billing_cycle: billing_cycle)
    unless charge_ids
      Failbot.push("gh.billing_cycle": billing_cycle, "gh.sponsors_listing.id": listing.id)
      raise MissingZuoraRatePlanChargeIdsError
    end
    flat_price = if tier.one_time?
      tier.to_money
    else
      tier.base_price(duration: plan_duration)
    end

    tracking_attributes = {
      Billing::Subscribable::ZUORA_TRACKING_FIELD.to_sym => tier.zuora_tracking_id,
    }

    # Enterprise accounts require tracking the org related to the subscription item so we can handle multiple
    # member orgs each sponsoring the same maintainer. The subscription item holds the org information.
    if item.account&.business?
      tracking_attributes.merge!({ subscription_item_id_field => item.id.to_s })
    end

    product_rate_plan_charges = [
      {
        productRatePlanChargeId: charge_ids[:flat],
        price: flat_price,
      }.merge!(tracking_attributes),
    ]

    if charge_ids[:fee].present?
      product_rate_plan_charges << {
        productRatePlanChargeId: charge_ids[:fee],
        price: item.sponsors_fee(flat_price),
      }.merge!(tracking_attributes)
    end

    product_rate_plan_charges
  end

  sig { returns T::Array[T::Hash[Symbol, T.any(String, Integer)]] }
  def github_charge_overrides
    zuora_charge_ids = plan.zuora_charge_ids(cycle: plan_duration)
    unless zuora_charge_ids
      Failbot.push("gh.plan_duration": plan_duration, "gh.plan": plan.to_s)
      raise MissingZuoraRatePlanChargeIdsError
    end

    overrides = if plan.per_seat?
      [{
        productRatePlanChargeId: zuora_charge_ids[:unit],
        quantity:  github_additional_seat_quantity,
      }]
    else
      []
    end

    overrides.push(plan_annual_discount_overrides) if plan_annual_discount_overrides.present?

    if plan_subscription.apple_iap_subscription? && plan.pro?
      overrides.push({
        # pro does not support seats so use :flat
        productRatePlanChargeId: zuora_charge_ids[:flat],
        price: 0
      })
    end

    if plan.business? && plan_subscription.seats < BUSINESS_PLAN_ASSUMED_MINIMUM
      overrides.push({
        productRatePlanChargeId: zuora_charge_ids[:base_unit],
        quantity: plan_subscription.seats,
      })
    elsif plan.business? && plan_subscription.seats >= BUSINESS_PLAN_ASSUMED_MINIMUM
      overrides.push({
        productRatePlanChargeId: zuora_charge_ids[:base_unit],
        quantity: BUSINESS_PLAN_ASSUMED_MINIMUM,
      })
    end

    overrides
  end

  sig { returns(T.nilable(ChargeOverrideParams)) }
  memoize def plan_annual_discount_overrides
    return unless plan.per_seat? && plan_duration == User::BillingDependency::YEARLY_PLAN
    unless billable_entity&.annual_discount_allowed?(plan: plan, billing_cycle: User::BillingDependency::YEARLY_PLAN)
      return
    end

    zuora_charge_ids = plan.zuora_charge_ids(cycle: plan_duration)
    unless zuora_charge_ids
      Failbot.push("gh.plan_duration": plan_duration, "gh.plan": plan.to_s)
      raise MissingZuoraRatePlanChargeIdsError
    end

    {
      productRatePlanChargeId: zuora_charge_ids[:annual_discount],
      discountPercentage: plan.yearly_discount_percentage
    }
  end

  sig { returns(T::Array[ChargeOverrideParams]) }
  def discount_overrides
    [{
      :productRatePlanChargeId => coupon.zuora_charge_ids(cycle: plan_duration)[coupon.zuora_charge_type],
      discount_charge_override_type => coupon_amount,
    }]
  end

  sig { params(uuid: Billing::ProductUUID).returns(T::Array[ChargeOverrideParams]) }
  def metered_usage_overrides_for(uuid)
    # Temporary method to get chargeOverrides for a metered ProductUUID. This will not be
    # necessary after migrating entitlements from Zuora
    if uuid.product_type == ::Billing::Actions::ZuoraProduct.product_type &&
      uuid.product_key == ::Billing::Actions::ZuoraProduct.private_visibility_rate_plan_charge.name
      return [{
        productRatePlanChargeId: uuid.zuora_product_rate_plan_charge_ids.values.first,
        includedUnits: plan.actions_included_private_minutes
      }]
    end
    if uuid.product_type == ::Billing::PackageRegistry::ZuoraProduct.product_type &&
      uuid.product_key == ::Billing::PackageRegistry::ZuoraProduct.product_key
      return [{
        productRatePlanChargeId: uuid.zuora_product_rate_plan_charge_ids[:bandwidth],
        includedUnits: plan.package_registry_included_bandwidth
      }]
    end
    if uuid.product_type == ::Billing::SharedStorage::ZuoraProduct.product_type &&
      uuid.product_key == ::Billing::SharedStorage::ZuoraProduct.product_key
      calculator = ::Billing::MeteredBilling::HourlyRateCalculator.new
      return [{
        productRatePlanChargeId: uuid.zuora_product_rate_plan_charge_ids[:usage],
        includedUnits: calculator.hourly_rate_for(units_per_month: plan.shared_storage_included_megabytes).round,
      }]
    end
    []
  end

  sig { returns(Integer) }
  def github_additional_seat_quantity
    if plan.business?
      # Hack to assume organizations on team plan ALWAYS have 5 seats as the default quantity
      # see https://github.com/github/gitcoin/issues/4241
      return [plan_subscription.seats - BUSINESS_PLAN_ASSUMED_MINIMUM, 0].max
    end

    if plan.base_cost?
      [plan_subscription.seats - plan.base_units, 0].max
    else
      plan_subscription.seats
    end
  end

  sig { returns(T.nilable(SubscriptionRatePlanParam)) }
  def github_lfs_plan
    return unless data_packs > 0
    {
      productRatePlanId: Asset::Status.zuora_id(cycle: plan_duration),
      chargeOverrides: [{
        productRatePlanChargeId: Asset::Status.zuora_charge_ids(cycle: plan_duration)[:unit],
        quantity: data_packs,
      }],
    }
  end

  sig { returns(T.nilable(SubscriptionRatePlanParam)) }
  def github_coupon
    return unless coupon
    {
      productRatePlanId: coupon.zuora_id(cycle: plan_duration),
      chargeOverrides: discount_overrides,
    }
  end

  sig { returns(Symbol) }
  memoize def discount_charge_override_type
    coupon.percentage? ? :discountPercentage : :discountAmount
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  def billable_rate_plans
    if user&.sponsors_customer_account && !plan_subscription.sponsors_purpose?
      # If the user has a Sponsors-specific customer account and this plan subscription ISN'T Sponsors-specific,
      # then we want to exclude anything Sponsors here:
      marketplace_rate_plans
    else
      # The plan subscription is purpose=general but the user does NOT have a Sponsors-specific customer account, so
      # we can include all types of rate plans:
      marketplace_rate_plans + sponsors_rate_plans
    end
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  def product_uuid_subscriptions_rate_plans
    product_sub_items = active_subscription_items.with_product_uuid_type.includes(:subscribable)
    product_sub_items.select(&:billable?).map do |item|
      {
        productRatePlanId: item.subscribable.zuora_product_rate_plan_id,
        chargeOverrides: product_uuid_overrides_for(item)
      }
    end
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  memoize def marketplace_rate_plans
    marketplace_sub_items = active_subscription_items.with_marketplace_listing_plans_type.includes(:subscribable)
    marketplace_sub_items.select(&:billable?).map do |item|
      {
        productRatePlanId: item.subscribable.zuora_id(cycle: plan_duration),
        chargeOverrides: marketplace_overrides_for(item),
      }
    end
  end

  sig { returns T::Array[Billing::SubscriptionItem] }
  memoize def sponsors_subscription_items
    items = active_subscription_items.for_sponsors_tiers
      .includes(:sponsorship, subscribable: :sponsors_listing)
      .select(&:billable?)
    tiers = items.map(&:subscribable).compact
    listings = tiers.map(&:sponsors_listing)
    billing_cycles = ([plan_duration] + tiers.map(&:billing_cycle).compact).uniq
    billing_cycles.each do |billing_cycle|
      # #product_uuid used by SponsorsListing#zuora_rate_plan_id in #sponsors_rate_plan_for
      # and SponsorsListing#zuora_rate_plan_charge_ids in #sponsors_overrides_for:
      GitHub::PrefillAssociations.prefill_batch_method(listings, :product_uuid, billing_cycle)
    end
    items
  end

  # Private: get a map associating active subscription items with their corresponding
  # Zuora rate plan.
  sig do
    returns(T::Hash[Billing::SubscriptionItem, T.nilable(SubscriptionRatePlanParam)])
  end
  memoize def sponsors_rate_plans_by_subscription_item
    sponsors_subscription_items.each_with_object({}) do |subscription_item, map|
      map[subscription_item] = sponsors_rate_plan_for(subscription_item)
    end
  end

  # Private: get a map associating Zuora rate plan IDs with their corresponding
  # active subscription item.
  sig { returns T::Hash[String, Billing::SubscriptionItem] }
  memoize def sponsors_subscription_items_by_rate_plan_id
    sponsors_subscription_items.each_with_object({}) do |subscription_item, map|
      rate_plan = sponsors_rate_plans_by_subscription_item[subscription_item]
      next unless rate_plan

      rate_plan_id = T.let(rate_plan[:productRatePlanId], T.nilable(String))
      if rate_plan_id.present?
        map[rate_plan_id] = subscription_item
      end
    end
  end

  # Private: Is this the duplicate addition of one time rate plan?
  #
  # We allow multiple payments, but folks must wait at least a day to make another payment since we currently
  # lack the tooling to de-duplicate properly.
  sig { params(candidate_rate_plan: SubscriptionRatePlanParam).returns(T::Boolean) }
  def duplicate_one_time_addition?(candidate_rate_plan)
    return false unless one_time_rate_plan?(candidate_rate_plan)
    end_date = active_effective_end_date(candidate_rate_plan)
    return false unless end_date

    GitHub::Billing.today.before?(end_date)
  end

  # Private: Get the max effective end date in Zuora for active rate plans related to the candidate rate plan.
  #
  # One-time rate plans are considered active beyond their effective end date. Retrieving the max (most recent)
  # of these supports determining how recently the candidate rate plan was applied.
  sig { params(candidate_rate_plan: SubscriptionRatePlanParam).returns(T.nilable(Date)) }
  def active_effective_end_date(candidate_rate_plan)
    active_zuora_rate_plans.select do |active_rate_plan|
      active_rate_plan.matches_candidate?(candidate_rate_plan, org_id_by_sub_item_id_mapping)
    end.flat_map { |active_rate_plan| active_rate_plan.rate_plan_charges }
      .map { |charge| charge.effective_end_date }
      .compact
      .max
  end

  sig { params(candidate_rate_plan: SubscriptionRatePlanParam).returns(T::Boolean) }
  def one_time_rate_plan?(candidate_rate_plan)
    one_time_product_rate_plan_ids.include?(candidate_rate_plan[:productRatePlanId])
  end

  sig { returns(T::Set[String]) }
  memoize def one_time_product_rate_plan_ids
    Billing::ProductUUID.where(
      zuora_product_rate_plan_id: current_rate_plan_ids,
      billing_cycle: "one_time"
    ).pluck(:zuora_product_rate_plan_id).to_set
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  memoize def sponsors_rate_plans
    sponsors_rate_plans_by_subscription_item.values.compact
  end

  sig do
    params(subscription_item: Billing::SubscriptionItem)
      .returns(T.nilable(SubscriptionRatePlanParam))
  end
  def sponsors_rate_plan_for(subscription_item)
    tier = T.let(subscription_item.subscribable, T.nilable(T.any(Billing::ProductUUID, Billing::Types::Subscribable)))
    return unless tier.is_a?(SponsorsTier)

    listing = tier.sponsors_listing
    return unless listing

    billing_cycle = T.let(tier.billing_cycle || plan_duration, T.any(String, Symbol))

    product_rate_plan_id = listing.zuora_rate_plan_id(billing_cycle: billing_cycle)
    unless product_rate_plan_id
      Failbot.push("gh.billing_cycle": billing_cycle, "gh.sponsors_listing.id": listing.id)
      raise MissingZuoraRatePlanChargeIdsError
    end

    {
      productRatePlanId: product_rate_plan_id,
      chargeOverrides: sponsors_overrides_for(subscription_item,
        listing: listing,
        tier: tier,
        billing_cycle: billing_cycle,
      ),
    }
  end

  sig { returns(T::Hash[String, T.nilable(String)]) }
  memoize def sponsors_contract_dates_by_rate_plan_id
    sponsors_subscription_items.each_with_object({}) do |subscription_item, contract_dates|
      tier = subscription_item.subscribable
      listing = tier.sponsors_listing
      billing_cycle = tier.billing_cycle || plan_duration
      listing_rate_plan_id = listing.zuora_rate_plan_id(billing_cycle: billing_cycle)
      contract_date = sponsors_contract_date_for(subscription_item)

      contract_dates[listing_rate_plan_id] = contract_date
    end
  end

  sig { returns T::Array[SponsorsTier] }
  memoize def sponsors_recurring_tiers
    sponsors_subscription_items.map(&:subscribable).select(&:recurring?)
  end

  sig { returns T::Array[String] }
  memoize def sponsors_recurring_tier_rate_plan_ids
    tier_ids = sponsors_recurring_tiers.map(&:id)
    return [] if tier_ids.empty?
    Billing::ProductUUID.sponsors_tiers.with_product_key(tier_ids)
      .where(billing_cycle: plan_duration).order(:zuora_product_rate_plan_id).pluck(:zuora_product_rate_plan_id)
  end

  sig { returns T::Array[String] }
  memoize def sponsors_recurring_listing_rate_plan_ids
    recurring_listing_keys = sponsors_recurring_tiers
      .map { |tier| tier.sponsors_listing&.product_key(billing_cycle: plan_duration) }
      .compact
    return recurring_listing_keys if recurring_listing_keys.empty?

    Billing::ProductUUID.sponsors_listings.with_product_key(recurring_listing_keys)
      .order(:zuora_product_rate_plan_id).pluck(:zuora_product_rate_plan_id)
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

    return unless user&.can_skip_sponsorship_proration?

    bill_cycle_day = T.must(user).customer_bill_cycle_day_for_sponsorships.to_i
    contract_date = GitHub::Billing.today

    if bill_cycle_day > contract_date.day && contract_date < contract_date.end_of_month
      contract_date = contract_date - 1.month
    end

    bill_cycle_day = [contract_date.end_of_month.day, bill_cycle_day].min

    backdated_date = contract_date.change(day: bill_cycle_day)
    # Zuora doesn't support backdating beyond the subscription effective date
    [backdated_date, zuora_subscription&.contract_effective_date].compact.max.to_s
  end

  sig { returns Billing::Money }
  memoize def payment_amount
    Billing::Money.new(plan_subscription.payment_amount * 100)
  end

  sig { returns T::Set[String] }
  memoize def current_rate_plan_ids
    Set.new(rate_plans.map { |plan| plan[:productRatePlanId] })
  end

  sig { returns T::Set[String] }
  memoize def active_zuora_rate_plan_ids
    Set.new(active_zuora_rate_plans.map { |plan| plan[:productRatePlanId] })
  end

  sig { returns T::Set[[String, Integer]] }
  memoize def active_zuora_business_marketplace_plan_ids
    Set.new(active_zuora_rate_plans.map do |active_rate_plan|
      [active_rate_plan.product_rate_plan_id, active_rate_plan.subscription_item_id]
    end)
  end

  # Public: get a list of active Zuora rate plans. For recurring subscriptions, this
  # includes subscriptions that haven't been canceled; for one-time subscriptions,
  # this includes subscriptions that were added/charged before the current day.
  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  memoize def active_zuora_rate_plans
    zuora_subscription&.active_rate_plans || []
  end

  sig { returns T::Set[String] }
  memoize def active_sponsors_otp_rate_plan_ids
    rate_plan_ids = zuora_subscription&.active_otp_rate_plans&.map { |plan| plan[:productRatePlanId] }
    return Set.new if rate_plan_ids.nil? || rate_plan_ids.empty?
    Billing::ProductUUID
      .sponsors
      .for_zuora_product_rate_plan(rate_plan_ids)
      .pluck(:zuora_product_rate_plan_id)
      .to_set
  end

  sig { returns T::Array[Billing::Zuora::RatePlan] }
  memoize def inactive_sponsors_otp_rate_plans
    rate_plans = zuora_subscription&.inactive_otp_rate_plans || []
    return [] if rate_plans.empty?
    rate_plan_ids = rate_plans.map { |plan| plan[:productRatePlanId] }
    sponsors_rate_plan_ids = Billing::ProductUUID
      .sponsors
      .for_zuora_product_rate_plan(rate_plan_ids)
      .pluck(:zuora_product_rate_plan_id)
      .to_set

    rate_plans.select do |plan|
      sponsors_rate_plan_ids.include?(plan[:productRatePlanId])
    end
  end

  sig { returns(String) }
  memoize def today
    GitHub::Billing.today.to_s
  end

  sig { returns T::Hash[Integer, Integer] }
  memoize def org_id_by_sub_item_id_mapping
    plan_subscription.org_id_by_sub_item_id
  end

  sig { returns T::Boolean }
  memoize def sponsors_self_serve_enterprise_feature_enabled?
    GitHub.flipper[:sponsors_self_serve_enterprise].enabled?(billable_entity)
  end

  sig { returns T::Boolean }
  def apply_credit_balance?
    # Sponsors-purpose customers lack an electronic payment method, so to prevent credit balance adjustments
    # from partially covering invoices (making the remaining balance uncollectible), we disable credit balance
    # adjustments for these customers.
    !customer&.sponsors_purpose?
  end

  sig { returns T::Boolean }
  def remove_duplicate_rate_plans_enabled?
    !!billable_entity&.feature_enabled?(:billing_remove_duplicate_rate_plans)
  end

  alias_method :order_date, :today
  alias_method :contract_effective_date, :today
  alias_method :subscription_start_date, :today
end
