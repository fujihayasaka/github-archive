# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module  Billing
  module Public
    # Public: The public Subscription Items API. All calls to manage specific subscription items should use this
    #         interface.
    #
    # Context: A Subscription (PlanSubscription to be precise) consist of one or more SubscriptionItems. A
    #          SubscriptionItem can represent a product like copilot, codespaces, or can represent a marketplace
    #          listing plan, or a sponsors tier.
    #
    class SubscriptionItem
      extend T::Sig

      class UnprocessableError < StandardError; end

      # Public: Returns the Integer identifier for this subscription item
      attr_reader :id

      # Public: Returns a Billing::Money describing the base price of this subscription item
      attr_reader :price

      # Public: Returns the Symbol describing the the billing cycle (e.g. :month or :year)
      attr_reader :interval

      # Public: Returns the String describing the name of the subscribable (e.g. "GitHub Copilot")
      attr_reader :name

      # Pubilc: Returns the String representing the global relay id
      attr_reader :global_relay_id

      delegate :cancel_and_refund!, :in_app_purchase?, :in_app_purchase, to: :model

      # Public: Create a subscription item
      #
      # product           - A Billing::ProductUUID or a Billing::Public::Product::ProductIdentifier that identifies the product we are subscribing to.
      # account           - The User account that purchased this
      # actor             - The User requesting the cancellation
      # quantity          - The Integer number of units/seats this product was purchased for (default: 1)
      # free_trial_length - The ActiveSupport::Duration for the free trial will (default: 0.days)
      # in_app_purchase   - Pass in to indicate the subscription was purchased via an in-app purchase. This will then override billing
      #                     and sure we do not double bill the customer since Apple or Google will handle billing.
      #
      # Examples
      #   # With ProductIdentifier:
      #   product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      #   result = Billing::Public::SubscriptionItem.create(
      #     product: product_identifier,
      #     account: monalisa,
      #     actor: monalisa,
      #     free_trial_length: 7.days
      #   )
      #   # => #<GitHub::Result:0x28d48 value: #<Billing::Public::SubscriptionItem interval: :month, ...>>
      #
      #   # With a ProductUUID:
      #   product_uuid = Billing::ProductUUID.find_sole_by(...)
      #   result = Billing::Public::SubscriptionItem.create(
      #     product: product_uuid,
      #     account: monalisa,
      #     actor: monalisa,
      #     free_trial_length: 7.days
      #   )
      #   # => #<GitHub::Result:0x91a4b value: #<Billing::Public::SubscriptionItem interval: :year, ...>>
      #
      #   result.ok?
      #   # => true
      #   result.value!
      #   # => #<Billing::Public::SubscriptionItem interval: :month, ...>
      #
      # Returns a GitHub::Result object that can either contain an error or a Billing::Public::SubscriptionItem
      sig do
        params(
          product: T.any(Billing::ProductUUID, Billing::Public::Product::ProductIdentifier),
          account: T.any(User, Business),
          actor: User,
          quantity: Integer,
          free_trial_length: ActiveSupport::Duration,
          is_stafftools_action: T::Boolean,
          skip_sync: T::Boolean,
          in_app_purchase: T.nilable(Billing::Public::InAppPurchase)
        ).returns(GitHub::Result).checked(:always).on_failure(:raise)
      end
      def self.create(product:, account:, actor:, quantity: 1, free_trial_length: 0.days, is_stafftools_action: false, skip_sync: false, in_app_purchase: nil)
        if product.is_a?(Billing::Public::Product::ProductIdentifier) && product.billing_cycle.nil?
          raise ArgumentError.new("Invalid product: #{product.serialize}. Missing billing_cycle key.")
        end

        subscribable = to_subscribable_types!(product).first

        GitHub::Result.new do
          # Create a SubscriptionItem and associate it to the account's PlanSubscription
          result = Billing::CreateProductSubscriptionItem.call(
            product_uuid: subscribable,
            quantity: quantity,
            account: account,
            viewer: actor,
            free_trial_length: free_trial_length,
            is_stafftools_action: is_stafftools_action,
            skip_sync: skip_sync,
            in_app_purchase: in_app_purchase
          )

          from_model(result[:subscription_item])
        end
      end

      sig do
        params(
          product: T.any(Billing::ProductUUID, Billing::Public::Product::ProductIdentifier),
          account: T.any(User, Business),
          actor: User,
          quantity: Integer,
          is_stafftools_action: T::Boolean,
        ).returns(GitHub::Result)
      end
      def self.update(product:, account:, actor:, quantity: 1, is_stafftools_action: false)
        subscribable = to_subscribable_types!(product).first

        GitHub::Result.new do
          result = Billing::UpdateSubscriptionItem.new(
              quantity: quantity,
              viewer: actor,
              subscribable: subscribable,
              plan_subscription: account.plan_subscription,
              is_stafftools_action: is_stafftools_action,
            ).call

          from_model(result.subscription_item)
        end
      end

      # Public: Get a user's subscription to a specific product
      #
      # product           - The optional Billing::Subscribable (e.g. Billing::ProductUUID, Marketplace::ListingPlan,
      #                     SponsorsTier, or Billing::Public::Product::ProductIdentifier).
      # account           - The User we are looking for a subscription under
      #
      # Examples
      #   # With ProductIdentifier:
      #   product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      #   result = Billing::Public::SubscriptionItem.all_active(product: product_identifier, account: monalisa)
      #   result.ok?
      #   # => true
      #   result.value!
      #   # => #<GitHub::Result:0x29a2c value: [#<Billing::Public::SubscriptionItem:0x00007f8097543a48 @id=1,...
      #
      #   # With a ProductUUID:
      #   product_query = { product_type: 'github.copilot', product_key: 'v0', billing_cycle: :month }
      #   copilot_product = Billing::ProductUUID.find_sole_by(product_query)
      #   result = Billing::Public::SubscriptionItem.all_active(product: copilot_product, account: monalisa)
      #   result.ok?
      #   # => true
      #   result.value!
      #   # => #<GitHub::Result:0x12c8b value: [#<Billing::Public::SubscriptionItem:0x00001b802c5132b8 @id=1,...
      #
      # Returns a GitHub::Result object that can either contain an error or an Array of
      # Billing::Public::SubscriptionItem
      sig do
        params(
          account: T.any(User, Organization, Business),
          product: T.nilable(T.any(Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, Billing::Public::Product::ProductIdentifier)),
        ).returns(GitHub::Result)
      end
      def self.all_active(account:, product: nil)
        # Handle case where account does not have a plan_subscription
        # (e.g. if account is a free user or EMU)
        return GitHub::Result.new { [] } if account.plan_subscription.nil?

        subscribables = to_subscribable_types!(product) if product.present?

        GitHub::Result.new do
          items_scope = T.must(account.plan_subscription).active_subscription_items
          items_scope = items_scope.where(subscribable: subscribables) if product.present?
          items_scope.map { |item| from_model(item) }
        end
      end

      # Public: Get a user's cancelled subscriptions to a specific product
      #
      # product           - The optional Billing::Subscribable (e.g. Billing::ProductUUID, Marketplace::ListingPlan,
      #                     SponsorsTier, or Billing::Public::Product::ProductIdentifier).
      # account           - The User we are looking for a subscription under
      #
      # Examples
      #   # With ProductIdentifier:
      #   product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      #   result = Billing::Public::SubscriptionItem.all_cancelled(product: product_identifier, account: monalisa)
      #   result.ok?
      #   # => true
      #   result.value!
      #   # => #<GitHub::Result:0x29a2c value: [#<Billing::Public::SubscriptionItem:0x00007f8097543a48 @id=1,...
      #
      #   # With a ProductUUID:
      #   product_query = { product_type: 'github.copilot', product_key: 'v0', billing_cycle: :month }
      #   copilot_product = Billing::ProductUUID.find_sole_by(product_query)
      #   result = Billing::Public::SubscriptionItem.all_cancelled(product: copilot_product, account: monalisa)
      #   result.ok?
      #   # => true
      #   result.value!
      #   # => #<GitHub::Result:0x12c8b value: [#<Billing::Public::SubscriptionItem:0x00001b802c5132b8 @id=1,...
      #
      # Returns a GitHub::Result object that can either contain an error or an Array of
      # Billing::Public::SubscriptionItem
      sig do
        params(
          account: T.any(User, Organization, Business),
          product: T.nilable(T.any(Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, Billing::Public::Product::ProductIdentifier)),
        ).returns(GitHub::Result)
      end
      def self.all_cancelled(account:, product: nil)
        # Handle case where account does not have a plan_subscription
        # (e.g. if account is a free user or EMU)
        return GitHub::Result.new { [] } if account.plan_subscription.nil?

        subscribables = to_subscribable_types!(product) if product.present?

        GitHub::Result.new do
          items_scope = T.must(account.plan_subscription).past_subscription_items
          items_scope = items_scope.where(subscribable: subscribables) if product.present?
          items_scope.map { |item| from_model(item) }
        end
      end

      # Public: Returns true if a trial exists for a given product
      #
      # product           - The Billing::Subscribable (e.g. Billing::ProductUUID, Marketplace::ListingPlan,
      #                     SponsorsTier, or Billing::Public::Product::ProductIdentifier).
      # account           - The User, Organization or Business we are looking for a subscription under
      #
      # within            - Optional: An ActiveSupport::TimeWithZone (e.g. 1.year.ago) that can be used to filter subscription items with free trials in this range
      #
      # Examples
      #   # With ProductIdentifier:
      #   product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.copilot", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      #   result = Billing::Public::SubscriptionItem.trial_exists(product: product_identifier, account: monalisa, within: 1.year.ago)
      #   result.ok?
      #   # => true
      #   result.value!
      #   # => #<GitHub::Result:0x29a2c value: true...
      #
      #   # With a ProductUUID:
      #   product_query = { product_type: 'github.copilot', product_key: 'v0', billing_cycle: :month }
      #   copilot_product = Billing::ProductUUID.find_sole_by(product_query)
      #   result = Billing::Public::SubscriptionItem.trial_exists(product: copilot_product, account: monalisa, within: 1.year.ago)
      #   result.ok?
      #   # => true
      #   result.value!
      #   # => #<GitHub::Result:0x12c8b value: false...
      #
      # Returns a GitHub::Result object that can either contain an error or a boolean
      sig do
        params(
          account: T.any(User, Organization, Business),
          product: T.any(Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, Billing::Public::Product::ProductIdentifier),
          within: T.nilable(Object) #TODO: If we use ActiveSupport::TimeWithZone directly, this throws a deprecation warning for ActiveSupport::TimeWithZone.name
        ).returns(GitHub::Result)
      end
      def self.trial_exists?(account:, product:, within: nil)
        # If we use ActiveSupport::TimeWithZone, the following deprecation is thrown.
        # Avoid this by using Object for now with a runtime type check.
        #
        # DEPRECATION WARNING: ActiveSupport::TimeWithZone.name has been deprecated and
        # from Rails 7.1 will use the default Ruby implementation.
        # You can set `config.active_support.remove_deprecated_time_with_zone_name = true`
        # to enable the new behavior now.
        return GitHub::Result.error(ArgumentError.new("within needs to be of type ActiveSupport::TimeWithZone")) unless within.nil? || within.is_a?(ActiveSupport::TimeWithZone)
        # Handle case where account does not have a plan_subscription
        # (e.g. if account is a free user or EMU)
        return GitHub::Result.new { false } if account.plan_subscription.nil?

        subscribables = to_subscribable_types!(product) if product.present?

        GitHub::Result.new do
          subscription_items = T.must(account.plan_subscription).subscription_items
          if within.present?
            subscription_items.where(subscribable: subscribables).where("free_trial_ends_on > ?", within).exists?
          else
            subscription_items.where(subscribable: subscribables).where.not(free_trial_ends_on: nil).exists?
          end
        end
      end

      # Public: Check if this user qualitifies for a free trial on this product
      #
      # product           - The Billing::Subscribable (e.g. Billing::ProductUUID, Marketplace::ListingPlan,
      #                     SponsorsTier, or Billing::Public::Product::ProductIdentifier)
      # account           - The user we are checking eligibility for
      #
      # Returns Boolean indicating eligibility
      sig { params(product: T.any(Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, Billing::Public::Product::ProductIdentifier), account: T.any(User, Business)).returns(T::Boolean) }
      def self.eligible_for_free_trial?(product:, account:)
        subscribables = to_subscribable_types_and_marketplace_listings!(product)

        subscribables.all? { |sub| account.eligible_for_free_trial_on?(product: sub) }
      end


      # Public: Schedule a subscription for cancellation
      #
      # product              - The subscribable (e.g. Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier,
      #                        or Billing::Public::Product::ProductIdentifier)
      # actor                - The User requesting the cancellation
      # force                - A boolean that determines whether we cancel the subscription at the end of the billing
      #                        interval, or cancel the subscription immediately (default: false).
      # allow_cancelling_iap - Apple is the source-of-truth for in-app purchases, so we do not
      #                        want to cancel them by default. You can override this by passing in
      #                        true and acknowledging this but it is not recommended given the user
      #                        must now be directed to cancel their subscription in-app.
      #
      # Examples
      #
      #   # With a Billing::ProductUUID argument:
      #   copilot_product = Billing::ProductUUID.find_sole_by(...)
      #
      #   result = Billing::Public::SubscriptionItem.cancel(product: copilot_product, actor: monalisa)
      #   # => #<GitHub::Result:0x28d48 value: #<Billing::Public::SubscriptionItem interval: :month, ...>>
      #   result.ok?
      #   # => true
      #
      # Returns a GitHub::Result object that can either contain an error or nothing
      sig do
        params(
          product: T.any(Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, Billing::Public::Product::ProductIdentifier),
          account: T.any(User, Organization, Business),
          actor: User,
          force: T::Boolean,
          skip_sync: T::Boolean,
          allow_cancelling_iap: T::Boolean
        ).returns(GitHub::Result)
      end
      def self.cancel(product:, account:, actor:, force: false, skip_sync: false, allow_cancelling_iap: false)
        GitHub::Result.new do
          items = all_active(product: product, account: account).value!
          raise BillingError.new("Can't cancel multiple subscription items") if items.count > 1
          item_id = items.first.id

          subscription_item = Billing::SubscriptionItem.find(item_id)
          result = subscription_item.cancel!(actor:, force:, skip_sync:, allow_cancelling_iap:).result
          raise BillingError.new(result.errors.join(", ")) unless result.success

          from_model(subscription_item)
        end
      end

      # Public: Schedule a cancelled subscription for reactivation
      #
      # product              - The subscribable (e.g. Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier,
      #                        or Billing::Public::Product::ProductIdentifier)
      # account              - The user we are reactivating the subscription for
      # actor                - The User requesting the cancellation
      # free_trial_length    - The number of free trial days to give the user after reactivation
      #
      # Examples
      #
      #   # With a Billing::ProductUUID argument:
      #   copilot_product = Billing::ProductUUID.find_sole_by(...)
      #
      #   result = Billing::Public::SubscriptionItem.reactivate(product: copilot_product, actor: monalisa)
      #   # => #<GitHub::Result:0x28d48 value: #<Billing::Public::SubscriptionItem interval: :month, ...>>
      #   result.ok?
      #   # => true
      #
      # Returns a GitHub::Result object that can either contain an error or nothing
      sig do
        params(
          product: T.any(Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, Billing::Public::Product::ProductIdentifier),
          account: T.any(User, Organization, Business),
          actor: User,
          free_trial_length: ActiveSupport::Duration,
        ).returns(GitHub::Result)
      end
      def self.reactivate(product:, account:, actor:, free_trial_length: 0.days)
        GitHub::Result.new do
          items = all_cancelled(product: product, account: account).value!
          raise BillingError.new("Can't reactivate multiple subscription items") if items.count > 1
          raise BillingError.new("Can't find a subscription to reactivate") if items.count == 0

          item_id = items.first.id

          subscription_item = Billing::SubscriptionItem.find(item_id)
          result = subscription_item.reactivate!(actor:, free_trial_length: free_trial_length, skip_sync: false).result
          raise BillingError.new(result.errors.join(", ")) unless result.success

          from_model(subscription_item)
        end
      end

      # Public: Schedule a subscription for cancellation and prorated refund
      #
      # product - The Billing::Subscribable (e.g. Billing::ProductUUID, Marketplace::ListingPlan, or SponsorsTier)
      # account   - The User that owns the subscription
      #
      # Examples
      #
      #   # With a product arguement:
      #   product_query = { product_type: 'github.copilot', product_key: 'v0', billing_cycle: :month }
      #   copilot_product = Billing::ProductUUID.find_sole_by(product_query)
      #
      #   result = Billing::Public::SubscriptionItem.cancel_and_refund(product: copilot_product, account: monalisa)
      #   # => #<GitHub::Result:0x28d48 value: #<Billing::Public::SubscriptionItem interval: :month, ...>>
      #   result.ok?
      #   # => true
      #
      # Returns a GitHub::Result object that can either contain an error or nothing
      def self.cancel_and_refund(product:, account:, organization: nil, full_refund: false, allow_cancelling_iap: false)
        GitHub::Result.new do
          items = all_active(product: product, account: account).value!
          raise BillingError.new("Can't cancel multiple subscription items") if items.count > 1
          item_id = items.first.id

          subscription_item = Billing::SubscriptionItem.find(item_id)

          enqueued = subscription_item.cancel_and_refund!(organization:, full_refund:, allow_cancelling_iap:)

          raise BillingError.new("Unable to enqueue cancellation job") unless enqueued

          from_model(subscription_item)
        end
      end

      # Public: Extends a trial to at most 60 days from today.
      #
      # product - The Billing::Subscribable
      # account - The User, Organization, or Business who owns the subscription
      #
      # Examples
      #
      #   # With ProductIdentifier:
      #   product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.advanced_security", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      #   result = Billing::Public::SubscriptionItem.extend_trial!(product: product_identifier, account: business, actor: owner, days: 7)
      #   result.ok?
      #   # => true
      #   result.value!
      #   # => #<GitHub::Result:0x29a2c value: #<Billing::Public::SubscriptionItem:0xXXXXXX
      #
      # Returns a GitHub::Result object that can either contain an error or the subscription item
      sig do
        params(
          product: T.any(Billing::Public::Product::ProductIdentifier, Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier),
          account: T.any(User, Business),
          actor: User,
          days: Integer,
          is_stafftools_action: T::Boolean
        ).returns(GitHub::Result)
      end
      def self.extend_trial!(product:, account:, actor:, days:, is_stafftools_action: false)
        items = all_active(product: product, account: account).value!
        return GitHub::Result.error(UnprocessableError.new("Can only extend one trial at a time")) if items.count > 1
        item_id = items.first.id

        subscription_item = Billing::SubscriptionItem.find(item_id)
        result = subscription_item.extend_trial!(actor: actor, days: days, is_stafftools_action: is_stafftools_action)
        return GitHub::Result.new { from_model(result.value!) } if result.ok?
        result
      end

      # Public: Ends a free trial immediately. If purchase_subscription is true, it will also keep the subscription
      #         and attempt to bill the customer.
      #
      # product - The Billing::Subscribable
      # account - The User, Organization, or Business who owns the subscription
      #
      # Examples
      #
      #   # With ProductIdentifier:
      #   product_identifier = Billing::Public::Product::ProductIdentifier.new(product_type: "github.advanced_security", product_key: "v0", billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month)
      #   result = Billing::Public::SubscriptionItem.end_free_trial_now!(product: product_identifier, account: business, purchase_subscription: true, seats: 5, actor: owner )
      #   result.ok?
      #   # => true
      #   result.value!
      #   # => #<GitHub::Result:0x29a2c value: #<Billing::Public::SubscriptionItem:0xXXXXXX
      #
      # Returns a GitHub::Result object that can either contain an error or the subscription item
      sig do
        params(
          product: T.any(Billing::Public::Product::ProductIdentifier, Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier),
          account: T.any(User, Business),
          actor: User,
          purchase_subscription: T::Boolean,
          seats: Integer,
          is_stafftools_action: T::Boolean,
          skip_sync: T::Boolean,
        ).returns(GitHub::Result)
      end
      def self.end_free_trial_now!(product:, account:, actor:, purchase_subscription:, seats: 0, is_stafftools_action: false, skip_sync: false)
        items = all_active(product: product, account: account).value!
        return GitHub::Result.error(UnprocessableError.new("Can only end one trial at a time")) if items.count > 1
        return GitHub::Result.error(UnprocessableError.new("Cannot end trial when trial is not active.")) if items.count == 0
        if purchase_subscription
          result = account.validate_purchases_allowed(actor: actor)
          return GitHub::Result.error(UnprocessableError.new(result.error_message)) if result.failed?
        end

        item_id = items.first.id
        subscription_item = Billing::SubscriptionItem.find(item_id)
        result = subscription_item.end_free_trial_now!(
          purchase_subscription: purchase_subscription,
          seats: seats,
          actor: actor,
          is_stafftools_action: is_stafftools_action,
          skip_sync: skip_sync,
        )
        return GitHub::Result.new { from_model(result.value!) } if result.ok?
        result
      end


      sig do
        params(
          product_type: String,
          account: User
        ).returns(T::Boolean)
      end
      def self.all_subscriptions_cancelled?(product_type:, account:)
        products = Billing::ProductUUID.where(product_type: product_type)
        return false unless products.any?

        subscription_items = account.subscription_items.where(subscribable: products)
        subscription_items.any? && !subscription_items.any?(&:active?)
      end

      # Public: Initialize a Subscription
      #
      # subscription_item - The Billing::SubscriptionItem ActiveRecord model we are wrapping
      sig { params(subscription_item: Billing::SubscriptionItem).void }
      def initialize(subscription_item)
        @id = subscription_item.id
        @global_relay_id = subscription_item.global_relay_id

        # TODO: Determine how we want to handle the other subscribable types (e.g. Marketplace::ListingPlan and
        # SponsorsTier)
        if subscription_item.subscribable.is_a?(Billing::ProductUUID)
          @interval = subscription_item.subscribable.billing_cycle.to_sym
          @price = subscription_item.subscribable.base_price(duration: interval)
          @name = subscription_item.subscribable.name
        end

        @model = subscription_item
      end

      def product_identifier
        cycle = Billing::Public::SubscriptionItems::BillingCycle.from_serialized(model.product_uuid.billing_cycle)

        Billing::Public::Product::ProductIdentifier.new(
          product_type: model.product_uuid.product_type,
          product_key: model.product_uuid.product_key,
          billing_cycle: cycle
        )
      end

      # Pubilc: Returns the Date when the free trial will end
      def free_trial_ends_on
        @free_trial_ends_on ||= model.free_trial_ends_on
      end

      # Pubilc: Returns the Date when the subscription item will be billed again
      def next_billing_date
        @next_billing_date ||= model.next_billing_date
      end

      # Public: Has this subscription been cancelled
      #
      # Returns true or false
      def cancelled? = model.quantity.zero?

      # Public: Is the subscription currently in the free trial period
      #
      # Returns true or false
      def on_free_trial?
        # The free trial ends at the *end* of the free_trial_ends_on day/date
        free_trial_ends_on.present? && GitHub::Billing.future?(free_trial_ends_on + 1.day)
      end

      # Public: Total number of availabe days in the free trial period
      #
      # Returns an Integer
      def free_trial_length
        return 0 unless free_trial_ends_on.present?

        created_on = model.created_at.in_time_zone(GitHub::Billing.timezone).to_date
        (free_trial_ends_on - created_on).to_i
      end

      # Public: How many days left in the subscription item's free trial. If the the free trial has passed, then we
      #         will return 0
      #
      # Returns a non-negative Integer
      def days_left_on_free_trial
        return @days_left_on_free_trial if defined?(@days_left_on_free_trial)

        @days_left_on_free_trial = 0
        if free_trial_ends_on.present? && free_trial_ends_on > GitHub::Billing.today
          @days_left_on_free_trial = (free_trial_ends_on - GitHub::Billing.today).to_i
        end

        @days_left_on_free_trial
      end

      # Public: How many days left in the subscription item.
      #
      # Returns an Integer or nil if subscription item is recurring
      def days_left_on_subscription
        return unless ends_on.present? && pending_cancellation?

        today = GitHub::Billing.today
        days_left = 0
        if ends_on > today
          days_left = (ends_on - today).to_i
        end

        days_left
      end

      # Public: The date when the subscription will end
      #
      # Returns a Date object
      def ends_on
        return nil unless pending_cancellation?

        next_billing_date.to_date
      end

      # Public: Is this subscription on a monthly billing interval?
      #
      # Returns true or false
      def monthly? = interval == :month

      # Public: Is this subscription on a yearly billing interval?
      #
      # Returns true or false
      def yearly? = interval == :year

      # Public: Is the subscription item pending cancellation?
      #
      # Returns true or false
      def pending_cancellation?
        pending_subscription_item_change&.cancellation?
      end

      # Public: The ID of the pending subscription item change
      #
      # Returns Numeric or Nil
      def pending_item_change_id
        pending_subscription_item_change&.id
      end

      ## Pending Product Changes
      # This section is for any changes that apply to the subscription item that would
      # require a new subscription item such as a duration change

      def pending_change?
        pending_product_change.present?
      end

      def pending_change_interval
        pending_product_change&.new_billing_cycle
      end

      def days_until_change
        return unless pending_product_change

        (pending_product_change.active_on - GitHub::Billing.today).to_i
      end

      def pending_product_change_id
        pending_product_change&.id
      end

      # Public: Quantity of the subscription item
      #
      # Returns an integer
      def quantity
        model.quantity
      end

      # Public: Is the subscription item billed via an Apple in-app purchase?
      #
      # Returns true or false
      def apple_in_app_purchase?
        model.apple_in_app_purchase?
      end

      # Public: Is the subscription item billed via a Google in-app purchase?
      #
      # Retursn true or false
      def google_in_app_purchase?
        model.google_in_app_purchase?
      end

      # Internal: Converts a Billing::Public::Product::ProductIdentifier to a Billing::Subscribable unless input is already a Billing::Subscribable
      #
      # product    - The Billing::Subscribable (e.g. Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, or Billing::Public::Product::ProductIdentifier)
      #
      # Returns an Array of Billing::Subscribable
      sig do
        params(
         product: T.any(Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, Billing::Public::Product::ProductIdentifier)
       ).returns(
         T::Array[T.any(Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier)]
       )
      end
      private_class_method def self.to_subscribable_types!(product)
        if product.is_a?(Billing::Public::Product::ProductIdentifier)
          Billing::ProductUUID.where(product.serialize).to_a
        else
          [product]
        end
      end

      # Internal: Converts a Billing::Public::Product::ProductIdentifier to a Billing::Subscribable unless input is already a Billing::Subscribable
      #           Converts a Marketplace::ListingPlan to a Marketplace::Listing
      #
      # product    - The Billing::Subscribable (e.g. Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, or Billing::Public::Product::ProductIdentifier)
      #
      # Returns an Array of Billing::Subscribable and Marketplace::Listing
      sig do
        params(
         product: T.any(Billing::ProductUUID, Marketplace::ListingPlan, SponsorsTier, Billing::Public::Product::ProductIdentifier)
       ).returns(
         T::Array[T.any(Billing::ProductUUID, T.nilable(Marketplace::Listing), SponsorsTier)]
       )
      end
      private_class_method def self.to_subscribable_types_and_marketplace_listings!(product)
        if product.is_a?(Billing::Public::Product::ProductIdentifier)
          Billing::ProductUUID.where(product.serialize).to_a
        elsif product.is_a?(Marketplace::ListingPlan)
          [product.listing]
        else
          [product]
        end
      end

      # Internal: Create a public subscription item object from the underlying model
      #
      # item - The Billing::SubscriptionItem ActiveRecord model representing the subscription item
      #
      # Returns a Billing::Public::SubscriptionItem
      private_class_method def self.from_model(item)
        new(item)
      end

      private

      # Internal: Returns the underlying Billing::SubscriptionItem model
      attr_reader :model

      # Internal: Get the pending subscription item change for this subscription item
      #
      # Returns a Billing::PendingSubscriptionItemChange or nil
      def pending_subscription_item_change
        return @pending_subscription_item_change if defined?(@pending_subscription_item_change)

        @pending_subscription_item_change = model.pending_subscription_item_change
      end

      # Internal: A pending change that swaps this subscription item with another in the same product
      #
      # Returns a Billing::PendingSubscriptionItemChange or nil
      def pending_product_change
        return @pending_product_change if defined?(@pending_product_change)

        @pending_product_change = model.pending_subscription_item_changes_for_product.first
      end
    end
  end
end
