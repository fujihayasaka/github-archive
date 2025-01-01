# typed: strict
# frozen_string_literal: true

module Billing
  # Public: Calculates pricing for a subscription, taking into account per-seat
  # pricing, data packs, marketplace subscriptions, and coupons. The account
  # object can be a User, Organization, or Business.
  #
  # Examples
  #
  #   pricing = Billing::Pricing.new(account: account_object)
  #   pricing.undiscounted.to_f
  #   # => 9.0
  #   pricing.discount.to_f
  #   # => 0.0
  #   pricing.discounted.to_f
  #   # => 9.0
  class Pricing
    include GitHub::Memoizer

    # Internal: Struct to hold a detailed breakdown of annual recurring revenue
    class AnnualRecurringRevenueDetail
      # Public: Returns the Billing::Pricing object used for calculations
      sig { returns Billing::Pricing }
      attr_reader :pricing

      # Public: Initializes the current AnnualRecurringRevenueDetail
      sig { params(pricing: Billing::Pricing).void }
      def initialize(pricing)
        @pricing = pricing
      end

      # Public: Calculates the annual recurring revenue from the account's plan
      # itself
      #
      # Returns the plan annual recurring revenue
      sig { returns Billing::Money }
      def plan
        pricing.discounted_plan_cost * annual_recurring_revenue_multiplier
      end

      # Public: Calculates the annual recurring revenue from additional seats
      # on the account's plan
      #
      # Returns the seat annual recurring revenue
      sig { returns Billing::Money }
      def seats
        pricing.discounted_seat_cost * annual_recurring_revenue_multiplier
      end

      # Public: Calculates the annual recurring revenue from data packs that the
      # account has or may purchase
      #
      # Returns the data pack annual recurring revenue
      sig { returns Billing::Money }
      def data_packs
        pricing.discounted_data_pack_cost * annual_recurring_revenue_multiplier
      end

      # Public: Calculates the annual recurring revenue from marketplace
      # subscription items
      #
      # Returns the marketplace annual recurring revenue
      sig { returns Billing::Money }
      def marketplace
        Billing::Money.new((
          pricing.marketplace_item_cost.cents *
          annual_recurring_revenue_multiplier *
          BillingTransaction.marketplace_revenue_cut
        ).floor)
      end

      # Public: Calculates the annual recurring revenue from
      # subscription addon items
      #
      # Returns the addons annual recurring revenue
      sig { returns Billing::Money }
      def addons
        return Billing::Money.zero unless pricing.addon_items.present?

        sum_in_cents = pricing.addon_items.sum do |item|
          item.respond_to?(:github_arr) ? T.unsafe(item).github_arr.cents : 0
        end
        Billing::Money.new(sum_in_cents)
      end

      # Public: Calculates the total annual recurring revenue from GitHub items
      # (i.e. excluding marketplace)
      #
      # Returns the total GitHub annual recurring revenues
      sig { returns Billing::Money }
      def github_total
        plan + seats + data_packs + addons
      end

      # Public: Calculates the total annual recurring revenue
      #
      # NOTE: sponsorships do not provide any annual recurring
      # revenue for GitHub and should not be added in
      #
      # Returns the total annual recurring revenue
      sig { returns Billing::Money }
      def total
        github_total + marketplace
      end

      # Public: Returns a multiplier to use for calculating annual recurring
      # revenue
      #
      # Returns either the integer 1 (yearly plan) or 12 (monthly plan)
      sig { params(duration: T.any(String, Symbol)).returns(Integer) }
      def annual_recurring_revenue_multiplier(duration: calculate_plan_duration)
        duration.to_s == User::BillingDependency::MONTHLY_PLAN ? 12 : 1
      end

      private

      # Internal: Returns string denoting the plan duration
      #
      # Returns either the string "month" or "year"
      sig { returns String }
      def calculate_plan_duration
        if pricing.monthly?
          User::BillingDependency::MONTHLY_PLAN
        else
          User::BillingDependency::YEARLY_PLAN
        end
      end
    end

    # Public: Returns the target User, Organization or Business.
    sig { returns T.nilable(Billing::Types::Account) }
    attr_reader :account

    # Public: Initializes the pricing calculation
    #
    # account            - A User, Organization or Business model (optional if
    #                      plan_subscription or plan_duration is provided)
    # plan_subscription  - The account's current PlanSubscription model, if any
    #                      (optional if account or plan_duration is provided)
    # plan               - The GitHub::Plan to use for price calculations if
    #                      different from the account's current plan (optional)
    # plan_duration      - The string plan duration to use for price calculations
    #                      if different from the account's current plan duration
    #                      (optional if account or plan_subscription is provided)
    # seats              - The integer number of total seats to use for price
    #                      calculations if different from the account's current
    #                      number of seats (optional)
    # data_packs         - The integer number of data packs to use for price
    #                      calculations if different from the account's current
    #                      number of data packs (optional)
    # subscription_item  - A new SubscriptionItem or PendingSubscriptionItemChange,
    #                      or an existing item with a different quantity as one
    #                      of the account's existing subscription items (optional;
    #                      can be used with subscription_items)
    # subscription_items - An array of new SubscriptionItems to be added or
    #                      changed to a different quantity and/or
    #                      PendingSubscriptionItemChanges (optional; can be
    #                      with subscription_item)
    # use_trial_prices   - Whether or not to use free trial prices for
    #                      marketplace items that are on or eligible for free
    #                      trials (default true)
    # coupon             - A Coupon to apply in pricing calculations (optional;
    #                      if omitted, the coupon on the current PlanSubscription
    #                      will be used if possible; cannot be used in
    #                      combination with the discount argument)
    # discount           - A raw discount value to be applied as a Numeric; can
    #                      be used in place of a Coupon object (optional; cannot
    #                      be used in combination with the coupon argument)
    # service_remaining  - A Numeric representing how much service is left for
    #                      the purpose of proration (default is 1 or 100% of the
    #                      service)
    # include_addons    - A boolean indicating whether or not to include subscription item product uuid pricing (default true)
    #                      This was added to avoid confusion in our settings/billing overview header, which does not
    #                      account for differences in billing cycles between a Pro plan and a subscription such as copilot and as a result
    #                      led to confusing results in the overview header after adding Copilot to this Pricing class.
    #                      This keyword argument can be removed once we have updated the UI. See https://github.com/github/gitcoin/issues/8857 for more details and progress on UI changes
    # include_metered_usage - A boolean indicating whether or not to include metered usage in the pricing calculation (default false)
    #                         This currently only factors in actions usage and was added to consider metered usage in the billing lock to prevent abuse.
    #                         The other metered products will be included in a follow up See: https://github.com/github/gitcoin/issues/9901
    # Raises ArgumentError if the required arguments are not provided
    sig do
      params(
        account: T.nilable(Billing::Types::Account),
        plan_subscription: T.nilable(Billing::PlanSubscription),
        plan: T.nilable(GitHub::Plan),
        seats: T.nilable(Integer),
        plan_duration: T.nilable(T.any(String, Symbol)),
        data_packs: T.nilable(Integer),
        subscription_item: T.nilable(T.any(Billing::SubscriptionItem, Billing::PendingSubscriptionItemChange)),
        subscription_items: T::Array[T.any(Billing::SubscriptionItem, Billing::PendingSubscriptionItemChange)],
        use_trial_prices: T::Boolean,
        coupon: T.nilable(Coupon),
        discount: T.nilable(Numeric),
        service_remaining: Numeric,
        include_addons: T::Boolean,
        include_metered_usage: T::Boolean
      ).void
    end
    def initialize(account: nil, plan_subscription: nil, plan: nil, seats: nil, plan_duration: nil, data_packs: nil, subscription_item: nil, subscription_items: [], use_trial_prices: true, coupon: nil, discount: nil, service_remaining: 1, include_addons: true, include_metered_usage: false)
      @account = account
      @plan_subscription = plan_subscription
      @new_plan = T.let(effective_plan(plan, account), T.nilable(GitHub::Plan))
      @new_seats = seats
      @new_plan_duration = T.let(plan_duration&.to_s, T.nilable(String))
      @new_data_packs = data_packs
      @new_subscription_items = T.let((subscription_items + [subscription_item]).compact,
        T::Array[T.any(Billing::SubscriptionItem, Billing::PendingSubscriptionItemChange)])
      @use_trial_prices = use_trial_prices
      @new_coupon = coupon
      @discount = discount
      @service_remaining = T.let(T.unsafe(service_remaining).to_r, Rational)
      @include_addons = include_addons
      @include_metered_usage = include_metered_usage

      if account.nil? && plan_subscription.nil? && plan_duration.nil?
        raise ArgumentError, "Billing::Pricing requires :account, :plan_subscription, " \
          "or :plan_duration to be provided"
      end

      if coupon && discount
        raise ArgumentError, "Billing::Pricing expects :coupon or :discount, " \
          "but cannot use both"
      end
    end

    sig do
      params(
        new_plan: T.nilable(GitHub::Plan),
        account: T.nilable(Billing::Types::Account)
      ).returns(T.nilable(GitHub::Plan))
    end
    def effective_plan(new_plan, account)
      return new_plan unless account
      if new_plan == account.plan
        GitHub::Plan.find(new_plan, account: account)
      else
        new_plan
      end
    end

    # Public: Calculates the undiscounted price for the account's subscription
    #
    # Returns the undiscounted price
    sig { returns Billing::Money }
    def undiscounted
      discountable + undiscountable
    end

    # Public: Calculates the discounted price for the account's subscription
    #
    # Returns the discounted price
    sig { returns Billing::Money }
    def discounted
      undiscounted - discount
    end

    # Public: Calculates the total discount for a account's subscription
    #
    # Returns the total discount
    sig { returns Billing::Money }
    def discount
      if @discount
        raw_discount
      else
        coupon_discount(coupon)
      end
    end

    # Public: Calculates the total undiscounted price for items which can
    # be discounted by a coupon
    #
    # Returns the discountable price
    sig { returns Billing::Money }
    def discountable
      prorated_plan_cost +
        prorated_seat_cost +
          prorated_data_pack_cost
    end

    # Public: Calculates the total undiscounted price for items which cannot
    # be discounted by a coupon
    #
    # Returns the undiscountable price
    sig { returns Billing::Money }
    def undiscountable
      total_undiscountable = prorated_marketplace_item_cost + prorated_recurring_sponsorable_item_cost

      total_undiscountable += prorated_addon_items_cost if @include_addons

      total_undiscountable += metered_usage_cost if @include_metered_usage

      total_undiscountable
    end

    # Public: Calculates the annual recurring revenue for the account's
    # subscription
    #
    # Returns the annual recurring revenue
    sig { returns Billing::Money }
    def annual_recurring_revenue
      annual_recurring_revenue_details.total
    end
    alias_method :arr, :annual_recurring_revenue

    # Public: Returns a breakdown of annual recurring revenue for a account's
    # subscription
    sig { returns AnnualRecurringRevenueDetail }
    memoize def annual_recurring_revenue_details
      AnnualRecurringRevenueDetail.new(self)
    end

    # Public: Calculates the price of the account's plan itself for the
    # applicable subscription duration
    #
    # Returns the plan price
    sig { returns Billing::Money }
    def plan_cost
      return Billing::Money.zero if !plan || active_plan_trial?

      if monthly?
        Billing::Money.new(T.must(plan).cost_in_cents)
      else
        Billing::Money.new(yearly_cost_in_cents)
      end
    end

    # Public: Calculates the price of the account's plan itself for the
    # applicable subscription duration, less any discounts
    #
    # Returns the discounted plan price
    sig { returns Billing::Money }
    def discounted_plan_cost
      plan_cost - plan_discount
    end

    # Public: Calculates the price of the account's plan itself for the
    # applicable subscription duration, prorated to the amount of
    # service remaining
    #
    # Returns the prorated plan price
    sig { returns Billing::Money }
    def prorated_plan_cost
      Billing::Money.new(prorate(plan_cost.cents))
    end

    # Public: Calculates the amount of discount applied to the account's plan
    #
    # Returns the plan discount
    sig { returns Billing::Money }
    def plan_discount
      return Billing::Money.zero if discountable.zero?
      Billing::Money.new((discount.cents * plan_cost.to_f / discountable.to_f).round)
    end

    # Public: Calculates the price of additional seats on the account's
    # plan (seats beyond the base number of seats included in the plan)
    #
    # Returns the seat price
    sig { returns Billing::Money }
    def seat_cost
      return Billing::Money.zero if !plan&.per_seat? || active_plan_trial?

      plan = T.must(self.plan)
      additional_seats = seats - plan.base_units
      additional_seats = 0 if additional_seats.negative?
      cost_per_seat = if monthly?
        Billing::Money.new(plan.unit_cost_in_cents)
      else
        Billing::Money.new(yearly_cost_in_cents)
      end

      cost_per_seat * additional_seats
    end

    # Public: Estimates the price of shared storage the account will pay based on
    # current usage and time remaining in billing cycle
    #
    # Returns the shared storage price
    sig { returns Billing::Money }
    def estimated_shared_storage_cost
      return Billing::Money.zero unless plan && T.must(plan).shared_storage_eligible?
      if account && !T.must(account).metered_billing_overage_allowed?(product: :shared_storage)
        return Billing::Money.zero
      end

      shared_storage_cost_in_cents = BigDecimal(Billing::SharedStorage::ZuoraProduct.unit_cost(account: account)) * 100 / (1.gigabyte / 1.megabyte)
      estimated_shared_storage_cost_cents = shared_storage_usage.estimated_monthly_paid_megabytes * shared_storage_cost_in_cents

      Billing::Money.new(estimated_shared_storage_cost_cents)
    end

    # Public: Calculates the price of additional seats on the account's
    # plan (seats beyond the base number of seats included in the plan), less
    # any discounts
    #
    # Returns the discounted seat price
    sig { returns Billing::Money }
    def discounted_seat_cost
      seat_cost - seat_discount
    end

    # Public: Calculates the price of the account's
    # plan and additional seats, less any discounts
    #
    # Returns the discounted price
    sig { returns Billing::Money }
    def discounted_plan_and_seat_cost
      discounted_plan_cost + discounted_seat_cost
    end

    # Public: Calculates the price of the account's
    # plan and additional seats. This does not include any add-ons.
    #
    # Returns the undiscounted plan seats price
    sig { returns Billing::Money }
    def plan_and_seat_cost
      plan_cost + seat_cost
    end

    # Public: Calculates the price of additional seats on the account's
    # plan (seats beyond the base number of seats included in the plan),
    # prorated to the amount of service remaining
    #
    # Returns the prorated seat price
    sig { returns Billing::Money }
    def prorated_seat_cost
      Billing::Money.new(prorate(seat_cost.cents))
    end

    # Public: Calculates the amount of discount applied to additional seats on
    # the account's plan
    #
    # Returns the seat discount
    sig { returns Billing::Money }
    def seat_discount
      return Billing::Money.zero if discountable.zero?
      Billing::Money.new((discount.cents * seat_cost.to_f / discountable.to_f).round)
    end

    # Public: Calculates the price of data packs that the account has or may
    # purchase
    #
    # Returns the data pack price
    sig { returns Billing::Money }
    def data_pack_cost
      return Billing::Money.zero unless data_packs

      Billing::Money.new(
        T.must(data_packs) *
        Asset::Status.data_pack_unit_price.cents *
        plan_duration_multiplier,
      )
    end

    # Public: Calculates the price of data packs that the account has or may
    # purchase, less any discounts
    #
    # Returns the discounted data pack price
    sig { returns Billing::Money }
    def discounted_data_pack_cost
      data_pack_cost - data_pack_discount
    end

    # Public: Calculates the price of data packs that the account has or may
    # purchase, prorated to the amount of service remaining
    #
    # Returns the prorated data pack price
    sig { returns Billing::Money }
    def prorated_data_pack_cost
      Billing::Money.new(prorate(data_pack_cost.cents))
    end

    # Public: Calculates the amount of discount applied to data packs that the
    # account has purchased
    #
    # Returns the data pack discount
    sig { returns Billing::Money }
    def data_pack_discount
      return Billing::Money.zero if discountable.zero?
      Billing::Money.new((discount.cents * data_pack_cost.to_f / discountable.to_f).round)
    end

    # Public: Calculates the price of marketplace subscription items that
    # the account has purchased
    #
    # Returns the marketplace subscription item price
    sig { returns Billing::Money }
    def marketplace_item_cost
      return Billing::Money.zero unless marketplace_items.present?

      subscription_item_cost(marketplace_items, plan_duration)
    end
    alias_method :marketplace_items_cost, :marketplace_item_cost

    # Public: Calculates the price of subscription item addons that
    # the account has purchased
    #
    # Returns the subscription item addons price
    sig { returns Billing::Money }
    def addons_cost
      return Billing::Money.zero unless addon_items.present?

      Billing::Money.new(addon_items.sum { |s| s.subscribable.base_price(duration: s.subscribable.billing_cycle).cents * s.quantity })
    end

    # Public: Calculates the total cost of metered usage items that
    # the account has purchased. (TODO: Include other metered usage products in the total cost)
    #
    # Returns the metered usage usage cost
    sig { returns Billing::Money }
    def metered_usage_cost
      actions_cost
    end

    # Public: Calculates the price of recurring sponsorship subscription items that
    # the account has purchased
    #
    # Returns the sponsorship subscription item price. Does not include the price of one-time sponsorships.
    sig { returns Billing::Money }
    def recurring_sponsorable_item_cost
      return Billing::Money.zero unless recurring_sponsorable_items.present?

      subscription_item_cost(recurring_sponsorable_items, plan_duration)
    end

    # Public: Gets the non-sponsorable subscription items
    #
    # Returns the subscription items that are not of listable types reflecting sponsorships
    sig { returns T::Array[T.any(Billing::SubscriptionItem, Billing::PendingSubscriptionItemChange)] }
    memoize def marketplace_items
      subscription_items.select(&:subscribable_Marketplace_ListingPlan?)
    end

    # Public: Gets the sponsorable subscription items for recurring sponsorships
    #
    # Returns the subscription items that are of listable types reflecting sponsorships, excluding one-time
    # sponsorships.
    sig { returns T::Array[T.any(Billing::SubscriptionItem, Billing::PendingSubscriptionItemChange)] }
    memoize def recurring_sponsorable_items
      subscription_items.select(&:subscribable_SponsorsTier?)
    end

    # Public: Gets the subscription addon items
    #
    # Returns the subscription items
    sig { returns T::Array[T.any(Billing::SubscriptionItem, Billing::PendingSubscriptionItemChange)] }
    memoize def addon_items
      subscription_items.select do |subscription_item|
        in_app_purchase = subscription_item.respond_to?(:in_app_purchase?) ? T.unsafe(subscription_item).in_app_purchase? : false
        paid = subscription_item.respond_to?(:paid?) ? T.unsafe(subscription_item).paid? : true

        subscription_item.subscribable_Billing_ProductUUID? && paid && !in_app_purchase
      end
    end

    # Public: Calculates the price of marketplace subscription items that
    # the account has purchased, prorated to the amount of service remaining
    #
    # Returns the prorated marketplace item price
    sig { returns Billing::Money }
    def prorated_marketplace_item_cost
      Billing::Money.new(prorate(marketplace_item_cost.cents))
    end

    # Public: Calculates the price of recurring sponsorable subscription items that
    # the account has purchased, prorated to the amount of service remaining
    #
    # Returns the prorated sponsorable item price. Omits the price of one-time sponsorships.
    sig { returns Billing::Money }
    def prorated_recurring_sponsorable_item_cost
      Billing::Money.new(prorate(recurring_sponsorable_item_cost.cents))
    end

    # Public: Calculates the price of copilot subscription items that
    # the account has purchased, prorated to the amount of service remaining
    #
    # Returns the prorated copilot item price
    sig { returns Billing::Money }
    def prorated_addon_items_cost
      Billing::Money.new(prorate(addons_cost.cents))
    end

    # Public: Calculates the price of package downloads the account has incurred
    sig { returns Billing::Money }
    def package_downloads_cost
      return Billing::Money.zero unless plan && T.must(plan).package_registry_eligible?
      unless account && T.must(account).metered_billing_overage_allowed?(product: :packages)
        return Billing::Money.zero
      end

      unit_cost = BigDecimal(::Billing::PackageRegistry::ZuoraProduct.unit_cost(account: account))
      Billing::Money.new(data_transfer_usage.billable_gigabytes * unit_cost * 100)
    end

    # Public: Calculates the price of actions the account has used
    #
    # Returns the actions price
    sig { returns Billing::Money }
    def actions_cost
      return Billing::Money.zero unless plan && T.must(plan).actions_eligible?
      return Billing::Money.zero unless account && T.must(account).metered_billing_overage_allowed?(product: :actions)

      total_usage_in_cents =
        begin
          Billing::UsageChecker.new(account: account).total_usage_in_cents
        rescue Billing::Platform::Api::Error => e
          Failbot.report(e)
          0
        end

      Billing::Money.new(total_usage_in_cents)
    end

    # Public: Whether or not this pricing calculation is for a monthly plan
    sig { returns T::Boolean }
    def monthly?
      plan_duration.to_s == User::BillingDependency::MONTHLY_PLAN
    end

    # Public: Allows prices to be prorated to a specific percentage without
    # initializing a new Pricing object
    #
    # service_remaining - A Numeric representing how much service is left for
    #                     the purpose of proration
    # block             - Block in which all pricing will be prorated to the
    #                     amount of service_remaining
    #
    # Examples
    #
    #   pricing.discounted.to_f
    #   # => 7.0
    #
    #   pricing.prorate_to(0.5) { pricing.discounted }.to_f
    #   # => 3.5
    #
    # Returns the result of the block
    sig do
      params(service_remaining: Numeric, block: T.proc.params(arg0: Pricing).returns(T.untyped)).returns(T.untyped)
    end
    def prorate_to(service_remaining, &block)
      old_service_remaining = @service_remaining
      @service_remaining = T.unsafe(service_remaining).to_r

      result = block.call(self)

      @service_remaining = old_service_remaining
      result
    end

    # Public: Allows prices to be calculated on a monthly basis without
    # initializing a new Pricing object
    #
    # block - Block in which all pricing will be calculated on a monthly basis
    #
    # Examples
    #
    #   pricing = Pricing.new(plan: GitHub::Plan.pro, plan_duration: "year")
    #
    #   pricing.discounted.to_f
    #   # => 84.0
    #
    #   pricing.monthly { pricing.discounted }.to_f
    #   # => 7.0
    #
    # Returns the result of the block
    sig { params(block: T.proc.params(arg0: Pricing).returns(T.untyped)).returns(T.untyped) }
    def monthly(&block)
      change_duration(User::BillingDependency::MONTHLY_PLAN, &block)
    end

    # Public: Allows prices to be calculated on a yearly basis without
    # initializing a new Pricing object
    #
    # block - Block in which all pricing will be calculated on a yearly basis
    #
    # Examples
    #
    #   pricing = Pricing.new(plan: GitHub::Plan.pro, plan_duration: "month")
    #
    #   pricing.discounted.to_f
    #   # => 7.0
    #
    #   pricing.yearly { pricing.discounted }.to_f
    #   # => 84.0
    #
    # Returns the result of the block
    sig { params(block: T.proc.params(arg0: Pricing).returns(T.untyped)).returns(T.untyped) }
    def yearly(&block)
      change_duration(User::BillingDependency::YEARLY_PLAN, &block)
    end

    private

    sig { returns Integer }
    def yearly_cost_in_cents
      return 0 unless plan = self.plan
      plan.yearly_cost_in_cents
    end

    sig { returns Billing::PackageRegistryUsage }
    memoize def data_transfer_usage
      Billing::PackageRegistryUsage.usage_quote(account)
    end

    sig { returns Billing::ActionsUsage }
    memoize def actions_usage
      Billing::ActionsUsage.product_usage(account)
    end

    sig { returns Billing::SharedStorageUsage }
    memoize def shared_storage_usage
      Billing::SharedStorageUsage.usage_quote(account)
    end

    # Internal: Sums the price of each passed subscription item
    #
    # items - an array of ::Billing::SubscriptionItem
    # duration - a string that will either be 'month' or 'year'
    sig do
      params(
        items: T::Array[T.any(Billing::SubscriptionItem, Billing::PendingSubscriptionItemChange)],
        duration: T.any(String, Symbol)
      ).returns(Billing::Money)
    end
    def subscription_item_cost(items, duration)
      items.reduce(Billing::Money.zero) do |memo, item|
        base_price_args = if item.subscribable_SponsorsTier?
          { include_fees: true, subscription_item: item }
        else
          {}
        end
        memo + item.price(duration: duration, trial_price: use_trial_prices?, **base_price_args)
      end
    end

    # Internal: Prorate a given amount for the amount of service remaining
    #
    # Truncates fractional cents, similar to Braintree and Zuora
    #
    # amount - amount for full service period
    #
    # Returns a prorated amount
    sig { params(amount: Numeric).returns(Integer) }
    def prorate(amount)
      (amount * @service_remaining).to_i
    end

    # Internal: The coupon that the account has currently redeemed or the
    # hypothetical coupon to use for pricing calculations
    sig { returns T.nilable(Coupon) }
    def coupon
      plan_subscription&.async_user&.sync
      @new_coupon || plan_subscription&.coupon || account&.coupon
    end

    # Internal: The discount from a hypothetical coupon to use for pricing
    # calculations
    #
    # potential_coupon        - The Coupon to use for pricing calculations; this
    #                           can be any Coupon object and needs not be
    #                           persisted or redeemed by the account
    # check_coupon_expiration - Whether or not to check the coupon's expiration
    #                           before applying the discount (default is true)
    #
    # Returns the coupon discount
    sig { params(potential_coupon: T.nilable(Coupon), check_coupon_expiration: T::Boolean).returns(Billing::Money) }
    def coupon_discount(potential_coupon, check_coupon_expiration: true)
      return Billing::Money.zero unless potential_coupon
      return Billing::Money.zero if coupon&.plan_specific? && coupon&.plan != plan
      return Billing::Money.zero if account&.will_be_expired? && check_coupon_expiration

      if potential_coupon.percentage?
        discount = potential_coupon.discount || 0
        Billing::Money.new(discount * discountable.cents)
      else
        Billing::Money.new([potential_coupon.discount_in_cents * plan_duration_multiplier, discountable.cents].min)
      end
    end

    # Internal: The discount from a raw discount value (rather than a coupon)
    # to use for pricing calculations
    #
    # Returns the discount
    sig { returns Billing::Money }
    def raw_discount
      hypothetical_coupon = Coupon.new(discount: @discount)
      coupon_discount(hypothetical_coupon, check_coupon_expiration: false)
    end

    # Internal: The current or hypothetical plan to use for pricing calculations
    sig { returns T.nilable(GitHub::Plan) }
    def plan
      @new_plan || plan_subscription&.plan || account&.plan
    end

    # Internal: The current or hypothetical plan duration to use for pricing
    # calculations
    #
    # Returns either the string 'month' or 'year'
    sig { returns String }
    def plan_duration
      T.must_because(@new_plan_duration || plan_subscription&.plan_duration || T.cast(account&.plan_duration, T.nilable(String))) do
        "#initialize ensures one of these is non-nil"
      end
    end

    # Internal: The current or hypothetical plan subscription to use for
    # pricing calculations
    sig { returns T.nilable(Billing::PlanSubscription) }
    def plan_subscription
      @plan_subscription || account&.plan_subscription
    end

    # Internal: Returns a multiplier to use for calculations where we need to
    # compute an annual cost ourselves
    #
    # Returns either the integer 1 (monthly plan) or 12 (yearly plan)
    sig { returns Integer }
    def plan_duration_multiplier
      if monthly?
        1
      else
        12
      end
    end

    # Internal: The current or hypothetical total number of seats (inclusive of
    # and seats included in a plan) to use for pricing calculations
    #
    # Returns number of seats
    sig { returns Integer }
    def seats
      @new_seats || plan_subscription&.seats || account&.seats || 0
    end

    # Internal: The current or hypothetical number of data packs to use for
    # pricing calculations
    #
    # Returns number of data packs
    sig { returns T.nilable(Integer) }
    def data_packs
      @new_data_packs || plan_subscription&.data_packs || account&.data_packs
    end

    # Internal: The current or hypothetical subscription items to
    # use for pricing calculations
    #
    # When @new_subscription_items has the same Marketplace::Listing as an
    # existing subscription item, it is assumed that we are changing the
    # listing plan or quantity of that item, and so pricing calculations will
    # be done on the new listing plan and quantity.
    sig { returns T::Array[T.any(Billing::SubscriptionItem, Billing::PendingSubscriptionItemChange)] }
    memoize def subscription_items
      customer = plan_subscription&.customer || account&.customer
      result = customer&.subscription_items&.includes(:subscribable).to_a

      # ignore existing one-time sponsorships when calculating price (they're paid!)
      result.reject! do |subscription_item|
        subscription_item.one_time_sponsorship?
      end

      if @new_subscription_items.any?
        # @new_subscription_items may have a different quantity than an existing
        # subscription for the same marketplace listing plan
        result.reject! do |existing_item|
          @new_subscription_items.any? do |new_item|
            new_item.async_listing.sync == existing_item.async_listing.sync
          end
        end
        result += @new_subscription_items
      end

      result
    end

    # Internal: Whether or not to use free trial prices for marketplace items
    # that are on or eligible for free trials
    sig { returns T::Boolean }
    def use_trial_prices?
      @use_trial_prices
    end

    # Internal: Allows prices to be calculated with a specific plan duration
    # without initializing a new Pricing object
    #
    # override_duration - The String plan duration to use for pricing
    #                     calculations ("month" or "year")
    # block             - Block in which all pricing will be calculated using
    #                     the specified plan duration
    #
    # Returns the result of the block
    sig do
      params(override_duration: String, block: T.proc.params(arg0: Pricing).returns(T.untyped)).returns(T.untyped)
    end
    def change_duration(override_duration, &block)
      if plan_duration == override_duration
        result = block.call(self)
      else
        old_duration = plan_duration
        @new_plan_duration = override_duration

        result = block.call(self)

        @new_plan_duration = old_duration
      end
      result
    end

    sig { returns T::Boolean }
    memoize def active_plan_trial?
      return false unless account.present? && account.respond_to?(:plan_trial_active?) # not a business
      non_biz_account = T.cast(account, T.any(User, Organization))
      plan = T.must_because(self.plan) { "#account being non-nil implies we will have a plan" }
      non_biz_account.plan_trial_active?(plan.name)
    end
  end
end
