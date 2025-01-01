# typed: strict
# frozen_string_literal: true

class Billing::PlanSubscription::ZuoraSubscriptionParams
  include FeatureFlagHelper
  include GitHub::Memoizer
  include Scientist

  module ISubscribeAmendRatePlanBuilder
    extend T::Helpers

    interface!

    sig { abstract.returns(T::Array[Billing::PlanSubscription::ZuoraSubscriptionParams::SubscriptionRatePlanParam]) }
    def rate_plans; end

    sig { abstract.returns(T::Hash[String, T.nilable(String)]) }
    def contract_dates_by_rate_plan_id; end

    # TODO: can we avoid this somehow?
    sig { abstract.returns(T::Boolean) }
    def non_github_product_rate_plans?; end
  end

  BUSINESS_PLAN_ASSUMED_MINIMUM = 5

  sig { returns Billing::PlanSubscription }
  attr_reader :plan_subscription

  sig { returns T.nilable(User) }
  attr_reader :user

  sig { returns T.nilable(::Billing::Types::Account) }
  attr_reader :billable_entity

  delegate \
    :coupon,
    :customer,
    :zuora_account_id,
    :zuora_subscription,
    :zuora_subscription_number,
    to: :plan_subscription

  delegate :rate_plans, to: :rate_plan_builder

  sig { returns(GitHub::Plan) }
  def plan
    # TODO: remove and delegate once plan has been typed in User billing dependency
    plan_subscription.plan
  end

  sig { returns T.nilable(Date) }
  def charged_through_date
    zuora_subscription&.charged_through_date
  end

  sig { params(plan_subscription: Billing::PlanSubscription).void }
  def initialize(plan_subscription:)
    @plan_subscription = plan_subscription
    @user = T.let(plan_subscription.user, T.nilable(User))
    @billable_entity = T.let(plan_subscription.billable_entity, T.nilable(::Billing::Types::Account))
    @pricing = T.let(Billing::Pricing.new(plan_subscription: plan_subscription), Billing::Pricing)
    @subscription_item_id_field = T.let(Billing::Zuora::RatePlanCharge::SUBSCRIPTION_ITEM_ID_FIELD.to_sym, Symbol)
    @rate_plan_builder = T.let(
      if plan_subscription.sponsors_purpose?
        Billing::PlanSubscription::ZuoraSponsorsSubscriptionRatePlanBuilder
      else
        Billing::PlanSubscription::ZuoraGeneralSubscriptionRatePlanBuilder
      end.new(plan_subscription),
      ISubscribeAmendRatePlanBuilder
    )

    Failbot.push(
      "gh.user.id": @user&.id,
      "gh.plan_subscription.id": @plan_subscription.id,
      "gh.billable_entity.id": @billable_entity&.id,
      "gh.billable_entity.type": @billable_entity&.class&.name,
    )
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
    T::Hash[Symbol, T.any(String, T.any(String, Billing::Types::Numeric))]
  end

  module SubscribeAmend
    class CreateSubscriptionParams < T::Struct
      prop :apply_credit_balance, T.nilable(T::Boolean), name: "applyCreditBalance"
      prop :account_key, String, name: "accountKey"
      prop :contract_effective_date, String, name: "contractEffectiveDate"
      prop :term_start_date, T.nilable(Date), name: "termStartDate"
      prop :term_type, String, name: "termType", default: "EVERGREEN"
      prop :subscribe_to_rate_plans, T::Array[SubscriptionRatePlanParam], name: "subscribeToRatePlans"
      prop :run_billing, T::Boolean, name: "runBilling", default: true
      prop :collect, T::Boolean

      # Sponsors-specific fields
      prop :gateway_id, T.nilable(String), name: "gatewayId"
      prop :invoice_separately, T.nilable(T::Boolean), name: "invoiceSeparately"
      prop :payment_gateway__c, T.nilable(String), name: "PaymentGateway__c"
    end
  end

  # Public: Generates the hash sent to Zuora to create the user's subscription, which includes the product
  # rate plans they're subscribing to, as well as the default processing options
  sig { returns(SubscribeAmend::CreateSubscriptionParams) }
  def create_params
    params = SubscribeAmend::CreateSubscriptionParams.new(
      apply_credit_balance: apply_credit_balance?,
      account_key: zuora_account_id,
      contract_effective_date: contract_effective_date,
      subscribe_to_rate_plans: rate_plans,
      run_billing: true,
      collect: collect_invoice_for_create_params?,
    )

    if plan_subscription.sponsors_purpose?
      params.gateway_id = GitHub.zuora_sponsors_payment_gateway_id
      params.invoice_separately = true
      params.payment_gateway__c = Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2
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

  private

  sig { returns(ISubscribeAmendRatePlanBuilder) }
  attr_reader :rate_plan_builder

  sig { returns Billing::Pricing }
  attr_reader :pricing

  sig { returns Symbol }
  attr_reader :subscription_item_id_field

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

    rate_plan_builder.non_github_product_rate_plans?
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
      found_rate_plan = active_zuora_rate_plans.find do |active_rate_plan|
        active_rate_plan.matches_candidate?(updated_plan, org_id_by_sub_item_id_mapping)
      end

      rate_plan = T.must(found_rate_plan)

      charge_updates = updated_plan[:chargeOverrides].each do |override|
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
      contract_effective_date = rate_plan_builder.contract_dates_by_rate_plan_id[rate_plan_id] || today

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
      next if one_time_rate_plan?(rate_plan)

      active_zuora_rate_plans.any? do |active_rate_plan|
        next unless active_rate_plan.matches_candidate?(rate_plan, org_id_by_sub_item_id_mapping)
        has_updated_charge_details?(rate_plan, active_rate_plan)
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
        active_rate_plan.matches_candidate?(local_rate_plan, org_id_by_sub_item_id_mapping)
      end
    end

    rate_plans_to_remove
  end

  sig { returns(T::Array[SubscriptionRatePlanParam]) }
  memoize def addition_rate_plans
    # Get a filtered list of rate plan hashes for adding to the user's subscription:
    plans = rate_plans.reject { |candidate_rate_plan| existing_rate_plan?(candidate_rate_plan) }

    plans += updated_discount_rate_plans if coupon && updated_discount_rate_plans
    plans
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
    discount_charge_override_type = coupon.percentage? ? :discountPercentage : :discountAmount
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
    Billing::Money.new(existing_price_in_cents) != Billing::Money.new(charge[:price].to_f * 100)
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

  class MissingZuoraRatePlanChargeIdsError < StandardError; end

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

  sig { returns(String) }
  memoize def today
    GitHub::Billing.today.to_s
  end

  sig { returns T::Hash[Integer, Integer] }
  memoize def org_id_by_sub_item_id_mapping
    plan_subscription.org_id_by_sub_item_id
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
