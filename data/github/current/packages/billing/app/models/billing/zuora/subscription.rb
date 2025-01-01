# typed: strict
# frozen_string_literal: true

class Billing::Zuora::Subscription
  include GitHub::Memoizer

  class NotFoundError < StandardError; end

  sig { params(zuora_id: T.nilable(String)).returns(T.nilable(T.attached_class)) }
  def self.find(zuora_id)
    return if zuora_id.nil?

    subscription = new(zuora_id)
    return unless subscription.found?

    subscription
  end

  sig { params(zuora_id: T.nilable(String)).returns(T.attached_class) }
  def self.find!(zuora_id)
    if sub = find(zuora_id)
      sub
    else
      raise NotFoundError, "Subscription not found for ID #{zuora_id}"
    end
  end

  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  attr_accessor :rate_plans

  sig { params(zuora_id: String, raw_subscription: T.nilable(T::Hash[Symbol, T.untyped])).void }
  def initialize(zuora_id, raw_subscription: nil)
    @raw_subscription = T.let(
      raw_subscription || GitHub.zuorest_client.get_subscription(zuora_id).with_indifferent_access,
      T::Hash[Symbol, T.untyped]
    )
    @rate_plans = T.let(build_rate_plans, T::Array[Billing::Zuora::RatePlan])
  end

  sig { returns(String) }
  def account_number
    raw_subscription[:accountNumber]
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def cancel
    GitHub.logger.info(
      "code.namespace": "Zuora::Subscription",
      "code.function": "cancel",
      "gh.billing.zuora.account.number": account_number,
      "gh.billing.zuora.subscription_number": number,
      "gh.billing.zuora.cancel.caller": caller_locations(1, 1)&.first&.label,
    )

    today = GitHub::Billing.today.to_s
    create_order_params = Billing::Zuora::Order::CreateParams.new(
      order_date: today,
      existing_account_number: account_number,
      processing_options: Billing::Zuora::Order::CreateParams::ProcessingOptions.new(
        run_billing: true,
        collect_payment: false,
      ),
      subscriptions: [
        Billing::Zuora::Order::CreateParams::Subscription.new(
          subscription_number: number,
          order_actions: [
            Billing::Zuora::OrderAction.new(
              type: Billing::Zuora::OrderAction::Type::CancelSubscription,
              cancel_subscription: Billing::Zuora::OrderAction::CancelSubscriptionParams.specific_date(cancellation_effective_date: today)
            )
          ]
        )
      ]
    )
    begin
      Billing::Zuora::Order.create(create_order_params).serialize
    rescue Zuorest::HttpError => e
      GitHub.logger.error({
        exception: e,
        "code.namespace": "Billing::Zuora::Subscription",
        "code.function": "cancel",
        "gh.billing.zuora.order.create_params": create_order_params.serialize,
      })
      response = e.data.stringify_keys
      unless response.dig("reasons", 0, "message").match(/The subscription is currently in a \(Suspended\) Status/).present?
        # Re-raise error for all other types of error messages
        raise e
      end

      response
    end
  end

  # Suspends the zuora subscription
  # The suspension will take place immediately unless specified in the options through
  # the suspendPolicy argument. For more options see https://www.zuora.com/developer/api-reference/#operation/PUT_SuspendSubscription
  # - After suspension, a subscription can only be resumed in the future. No same day resume
  # - After suspension, a subscription's ID changes
  # - A subscription cannot be amended if it is suspended.
  # - EffectiveEndDate gets set to the suspension date.
  sig { params(options: T.untyped).returns(T::Hash[String, T.untyped]) }
  def suspend(**options)
    response = GitHub.zuorest_client.suspend_subscription(number, {
      extendsTerm: false,
      resume: false,
      suspendPolicy: "Today",
    }.merge!(options))

    if response["success"]
      raw_subscription[:id] = response["subscriptionId"]
    end

    response
  end

  # Resumes the zuora subscription
  # The resume will take place immediately unless specified in the options through
  # the resumePolicy argument. For more options see https://www.zuora.com/developer/api-reference/#operation/PUT_ResumeSubscription
  # - After resume, a subscription can only be suspended in the future. No same day suspension
  # - After resume, a subscription's ID changes
  sig { params(options: T.untyped).returns(T::Hash[String, T.untyped]) }
  def resume(**options)
    response = GitHub.zuorest_client.resume_subscription(number, {
      collect: false,
      runBilling: true,
      resumePolicy: "Today",
    }.merge!(options), ::Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER)

    if response["success"]
      raw_subscription[:id] = response["subscriptionId"]
    end

    response
  end

  sig { returns(T::Boolean) }
  def found?
    raw_subscription[:success]
  end

  sig { returns(T::Boolean) }
  def active?
    status == "Active"
  end

  sig { returns(Date) }
  def start_date
    Date.parse(raw_subscription[:subscriptionStartDate])
  end

  sig { returns(Date) }
  def contract_effective_date
    Date.parse(raw_subscription[:contractEffectiveDate])
  end

  sig { returns(T::Boolean) }
  def pending?
    return false if raw_subscription[:contractEffectiveDate].blank?

    GitHub::Billing.timezone.parse(raw_subscription[:contractEffectiveDate]).future?
  end

  sig { returns(T::Boolean) }
  def cancelled?
    status == "Cancelled"
  end

  sig { returns(T::Boolean) }
  def suspended?
    status == "Suspended"
  end

  # Whether the subscription has a past due invoice
  sig { returns(T::Boolean) }
  memoize def past_due?
    Billing::Zuora::Invoice.past_due(account_id: raw_subscription[:accountId]).any?
  end

  sig { returns(T::Boolean) }
  def has_active_github_plan?
    !!active_github_rate_plan
  end

  sig { params(subscription_items: T::Array[::Billing::SubscriptionItem]).returns(T::Boolean) }
  def subscription_items_synchronized?(subscription_items)
    github_product_rate_plan_ids = subscription_items.map(&:product_uuid).compact.map(&:zuora_product_rate_plan_id)
    zuora_product_rate_plan_ids  = subscribable_rate_plans.map(&:product_rate_plan_id)

    github_product_rate_plan_ids.difference(zuora_product_rate_plan_ids).none? &&
      zuora_product_rate_plan_ids.difference(github_product_rate_plan_ids).none?
  end

  # Active rate plans tied to the subscription
  # This excludes plans that have been scheduled for removal in Zuora due to a downgrade
  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  def active_rate_plans
    rate_plans.select(&:active?)
  end

  # Inactive rate plans tied to the subscription
  # This includes plans that have been scheduled for cancellation, but not yet cancelled
  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  def cancelled_rate_plans
    rate_plans.select(&:inactive?)
  end

  # OTP rate plans tied to the subscription
  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  def otp_rate_plans
    rate_plans.select(&:one_time_plan?)
  end

  # Active OTP rate plans tied to the subscription
  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  def active_otp_rate_plans
    otp_rate_plans.select(&:active?)
  end

  # Inactive OTP rate plans tied to the subscription
  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  def inactive_otp_rate_plans
    otp_rate_plans.select(&:inactive?)
  end

  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  def subscribable_rate_plans
    rate_plans.select do |plan|
      subscribable_product_rate_plan_ids.include?(plan.product_rate_plan_id)
    end
  end

  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  def active_subscribable_rate_plans
    subscribable_rate_plans.select(&:active?)
  end

  # Returns all rate plan charges
  sig { returns(T::Array[Billing::Zuora::RatePlanCharge]) }
  def rate_plan_charges
    rate_plans.flat_map(&:rate_plan_charges)
  end

  # Returns all active rate plan charges
  sig { returns(T::Array[Billing::Zuora::RatePlanCharge]) }
  def active_rate_plan_charges
    rate_plan_charges.select(&:active?)
  end

  # Number of seats in the subscription in addition to the base seats
  sig { returns(Integer) }
  def seats
    plan = self.plan
    return 0 if plan.nil? || !plan.per_seat?
    return 0 unless has_active_github_plan?

    github_rate_plan = T.must(active_github_rate_plan)

    charge_ids = T.must(plan.zuora_charge_ids(cycle: plan_duration))

    seats_rate_plan_charge_id = charge_ids[:unit]
    seats_rate_plan_charge = github_rate_plan[:ratePlanCharges].detect do |rate_plan_charge|
      rate_plan_charge[:productRatePlanChargeId] == seats_rate_plan_charge_id
    end

    if plan.business?
      default_seats_rate_plan_charge_id = charge_ids[:base_unit]
      default_seats_rate_plan_charge = github_rate_plan[:ratePlanCharges].detect do |rate_plan_charge|
        rate_plan_charge[:productRatePlanChargeId] == default_seats_rate_plan_charge_id
      end

      # workaround, we always expect a default of 1 seat but we need to add the
      # "default seat" rate plan's to the quantity due to the < 5 seats workaround
      (seats_rate_plan_charge[:quantity].to_i + default_seats_rate_plan_charge[:quantity].to_i) - 1
    else
      seats_rate_plan_charge[:quantity].to_i
    end
  end

  # Number of data packs in the subscription
  sig { returns(Integer) }
  memoize def data_packs
    rate_plan_id = Asset::Status.zuora_id(cycle: plan_duration)
    data_pack_rate_plan = active_rate_plans.detect do |plan|
      plan[:productRatePlanId] == rate_plan_id
    end
    return 0 unless data_pack_rate_plan

    rate_plan_charge_id = Asset::Status.zuora_charge_ids(cycle: plan_duration)[:unit]
    rate_plan_charge = data_pack_rate_plan[:ratePlanCharges].detect do |charge|
      charge[:productRatePlanChargeId] == rate_plan_charge_id
    end
    return 0 unless rate_plan_charge

    rate_plan_charge[:quantity].to_i
  end

  # The outstanding balance for the account
  sig { returns(::Billing::Types::Numeric) }
  def balance
    zuora_account[:metrics][:balance]
  end

  # The active payment amount of the subscription based on the duration in months,
  # minus the user's discounts
  sig { params(plan_duration_in_months: Integer).returns(Billing::Money) }
  def payment_amount(plan_duration_in_months:)
    contracted_mrr * plan_duration_in_months - discount
  end

  # The date that the subscription has been charged through.
  sig { params(product_rate_plan_charge_id: T.nilable(String)).returns(Date) }
  def charged_through_date_for(product_rate_plan_charge_id:)
    return GitHub::Billing.today if product_rate_plan_charge_id.blank?

    charge = active_rate_plan_charges.detect do |charge|
      charge.product_rate_plan_charge_id == product_rate_plan_charge_id
    end
    charged_through_date = charge&.charged_through_date
    return GitHub::Billing.today if charged_through_date.nil?

    charged_through_date
  end

  # The date that the subscription has been charged through. This does not always
  # line up with the next bill date, as we bill for usage based products every month.
  sig { returns(Date) }
  def charged_through_date
    active_charged_through_date || GitHub::Billing.today
  end
  alias_method :next_billing_date, :charged_through_date

  # Public: The charge through date from the active rate plans
  sig { returns(T.nilable(Date)) }
  def active_charged_through_date
    charges = if active_billing_period_varies?
      # Monthly Actions rate plan - but other rate plans are annual
      active_rate_plan_charges_following_github_plan_billing_interval.select(&:annual?)
    else
      active_rate_plan_charges_following_github_plan_billing_interval
    end

    charges = copilot_rate_plan_charges if charges.blank?

    # Select the first charge with a charged through date (ignoring one-time charges)
    charge = charges.detect do |charge|
      charge.charged_through_date.present? && !charge.one_time?
    end
    return unless charge

    if charge.usage?
      T.must(charge.charged_through_date) + 1.month
    else
      charge.charged_through_date
    end
  end

  # The current GitHub plan on the subscription
  sig { returns(T.nilable(GitHub::Plan)) }
  def plan
    @plan ||= T.let(GitHub::Plan.find(github_plan_product&.product_key), T.nilable(GitHub::Plan))
  end

  # The type of billing cycle the subscription is currently on based on its active rate plans
  sig { returns(String) }
  def plan_duration
    billing_period.to_s.downcase == "annual" ? User::BillingDependency::YEARLY_PLAN : User::BillingDependency::MONTHLY_PLAN
  end

  # Public: The total discount amount
  sig { returns(Billing::Money) }
  def discount
    return Billing::Money.new(0) unless discounts.any?
    Billing::Money.new(sum_discounts * 100)
  end

  # The versioned 32 character ID for the Zuora subscription
  sig { returns(String) }
  def id
    raw_subscription[:id]
  end

  # The short form ID for the Zuora subscription
  sig { returns(String) }
  def number
    raw_subscription[:subscriptionNumber]
  end

  sig { returns(String) }
  def status
    raw_subscription[:status]
  end

  sig { returns(String) }
  def term_start_date
    raw_subscription[:termStartDate]
  end

  sig { returns(String) }
  def dashboard_url
    "#{GitHub.zuora_host}/apps/Subscription.do?method=view&id=%s" % [id]
  end

  sig { returns(Zuorest::Model::Account) }
  def zuora_account
    @zuora_account ||= T.let(Zuorest::Model::Account.find(raw_subscription[:accountId]), T.nilable(Zuorest::Model::Account))
  end

  # Public: The GitHub Rate Plan that is active
  sig { returns(T.nilable(Billing::Zuora::RatePlan)) }
  def active_github_rate_plan
    return unless github_plan_product = self.github_plan_product

    @_active_github_rate_plan ||= T.let(active_rate_plans.find do |rate_plan|
      rate_plan.product_rate_plan_id == github_plan_product.zuora_product_rate_plan_id
    end, T.nilable(Billing::Zuora::RatePlan))
  end

  # Public: Does this subscription require its own invoices?
  sig { returns(T::Boolean) }
  def invoice_separately?
    !!raw_subscription[:invoiceSeparately]
  end

  # Public: The purpose of this subscription, like what kind of purchases can be made
  # on this subscription.
  sig { returns(Symbol) }
  def purpose
    payment_gateway = raw_subscription[Billing::PlanSubscription::PAYMENT_GATEWAY_FIELD.to_sym]
    if payment_gateway == Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2
      :sponsors
    else
      :general
    end
  end

  private

  sig { returns(T::Hash[Symbol, T.untyped]) }
  attr_reader :raw_subscription

  sig { returns(T::Array[Billing::Zuora::RatePlan]) }
  def build_rate_plans
    return [] if raw_subscription[:ratePlans].nil?

    raw_subscription[:ratePlans].map do |rate_plan_hash|
      Billing::Zuora::RatePlan.new(rate_plan_hash)
    end
  end

  sig { returns(T::Array[Billing::Zuora::RatePlanCharge]) }
  def copilot_rate_plan_charges
    copilot_charge_ids = Billing::ProductUUID.copilot.flat_map(&:charges).map(&:zuora_product_rate_plan_charge_id)

    active_rate_plan_charges.select do |charge|
      copilot_charge_ids.include?(charge.product_rate_plan_charge_id)
    end
  end

  sig { returns(T::Array[Billing::Zuora::RatePlanCharge]) }
  def active_rate_plan_charges_following_github_plan_billing_interval
    active_rate_plan_charges - copilot_rate_plan_charges
  end

  # Private: Amount that an active percentage coupon is discounting over eligible charges.
  sig { params(percentage_discount_charge: ::Billing::Zuora::RatePlanCharge).returns(Float) }
  def percentage_discounted_amount(percentage_discount_charge)
    percentage_discount_charge["discountApplyDetails"].reduce(0) do |eligible_charge_amount, apply_details|
      discount_eligible_rate_plan = active_rate_plans.detect do |rate_plan|
        rate_plan["productRatePlanId"] == apply_details["appliedProductRatePlanId"]
      end

      if discount_eligible_rate_plan
        discount_eligible_rate_plan["ratePlanCharges"].each do |rate_plan_charge|
          eligible_charge_amount += rate_plan_charge["price"] * rate_plan_charge["quantity"]
        end
      end

      eligible_charge_amount
    end * (percentage_discount_charge["discountPercentage"] / 100)
  end

  # Private: All discounts on the Zuora subscription.
  sig { returns(T::Array[::Billing::Zuora::RatePlan]) }
  def discounts
    return [] unless active_rate_plans.any?

    active_rate_plans.select do |rate_plan|
      rate_plan.product_name.include?("Discount")
    end
  end

  # Private: The sum of all discounts on the wrapped Zuora subscription
  sig { returns(Float) }
  def sum_discounts
    discounts.sum do |discount|
      discount.rate_plan_charges.sum do |rate_plan_charge|
        if rate_plan_charge.discount_percentage
          percentage_discounted_amount(rate_plan_charge)
        else
          rate_plan_charge.discount_amount
        end.to_f
      end
    end.to_f
  end

  # Private: Is the discount a percentage?
  sig { returns(T::Boolean) }
  def percentage_discount?
    discounts.any? do |discount|
      discount["ratePlanCharges"].any? { |charge| charge["discountPercentage"].present? }
    end
  end

  # Private: The billing period of the current subscription
  sig { returns(T.nilable(String)) }
  def billing_period
    @_billing_period ||= T.let(
      if active_billing_period_varies?
        # Monthly Actions rate plan - but other rate plans are annual
        "Annual"
      else
        active_rate_plan_charges_following_github_plan_billing_interval.map(&:billing_period).compact.first
      end, T.nilable(String)
    )
  end

  # Private: Does the billing period in active rate plan charges vary?
  sig { returns(T::Boolean) }
  def active_billing_period_varies?
    active_rate_plan_charges_following_github_plan_billing_interval.map(&:billing_period).compact.uniq.length > 1
  end

  # Private: The GitHub ProductUUID associated with subscription
  sig { returns(T.nilable(Billing::ProductUUID)) }
  def github_plan_product
    return @_github_plan_product if @_github_plan_product

    rate_plan_ids = active_rate_plans.map { |rate_plan| rate_plan[:productRatePlanId] }

    # There should only be one active product rate plan for a github plan
    @_github_plan_product = T.let(
      Billing::ProductUUID.for_zuora_product_rate_plan(rate_plan_ids).where(product_type: "github.plan").first,
      T.nilable(Billing::ProductUUID)
    )
  end

  sig { returns(T::Array[String]) }
  def subscribable_product_rate_plan_ids
    @subscribable_product_rate_plan_ids ||= T.let(Billing::ProductUUID.subscribable.map(&:zuora_product_rate_plan_id), T.nilable(T::Array[String]))
  end

  sig { returns(::Billing::Money) }
  def contracted_mrr
    Billing::Money.new(raw_subscription[:contractedMrr] * 100)
  end
end
