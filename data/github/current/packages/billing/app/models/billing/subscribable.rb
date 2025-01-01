# typed: strict
# frozen_string_literal: true

module Billing
  module Subscribable
    extend T::Helpers
    extend ActiveSupport::Concern

    ZUORA_TRACKING_FIELD = "Subscribable_Tracking_Id__c"

    requires_ancestor { Kernel }

    abstract!

    included do
      T.bind(self, Billing::Types::SubscribableClasses)

      has_many :billing_transaction_line_items,
               class_name: "Billing::BillingTransaction::LineItem",
               as: :subscribable, inverse_of: :subscribable

      has_one :last_billing_transaction_line_item,
              -> { order(created_at: :desc) },
              class_name: "Billing::BillingTransaction::LineItem",
              as: :subscribable
    end

    class_methods do

      # Public: whether Zuora tracking is enabled for a given class. Defaults to true for
      # any class that includes this concern.
      #
      # Classes without zuora tracking enabled will not be resolved in self.from_tracking_ids.
      sig { returns(T::Boolean) }
      def zuora_tracking_enabled?
        true
      end
    end

    sig { returns(T::Boolean) }
    def zuora_tracking_enabled?
      T.bind(self, Billing::Types::Subscribable)

      self.class.zuora_tracking_enabled?
    end

    sig { abstract.returns(T.nilable(Integer)) }
    def listing_id; end

    sig { abstract.returns(T.untyped) }
    def listing; end

    sig { abstract.returns(T.nilable(String)) }
    def name; end

    sig { abstract.returns(T.nilable(Integer)) }
    def monthly_price_in_cents; end

    sig { abstract.returns(T.nilable(Integer)) }
    def yearly_price_in_cents; end

    sig { abstract.returns(T::Boolean) }
    def for_users_only?; end

    sig { abstract.returns(T::Boolean) }
    def for_organizations_only?; end

    # Public: Is this subscribable one that a user can have an active subscription for while also having an
    # active subscription for the specified other subscribable?
    sig { params(other_subscribable: T.nilable(Billing::Types::Subscribable)).returns(T::Boolean) }
    def can_be_concurrent_with_subscription_item_for?(other_subscribable)
      T.bind(self, Billing::Types::Subscribable)

      return true if other_subscribable.nil?

      # It's fine for a user to have an active sponsorship while also having an active Marketplace subscription
      return true unless other_subscribable.is_a?(self.class)

      # It's fine for a user to have active subscriptions for two different Marketplace listings or two different
      # sponsorable maintainers
      listing_id != other_subscribable.listing_id
    end

    # Public: batch lookup of subscribables from a list of zuora tracking IDs
    #
    # Implementation borrowed from Platform::Helpers::NodeIdentification.from_global_id
    #
    # Returns [Billing::Subscribable]
    sig do
      params(tracking_ids: T::Array[String])
        .returns(T::Hash[String, Billing::Types::Subscribable])
    end
    def self.from_tracking_ids(tracking_ids)
      # Each tracking ID decodes to a [subscribable_type, subscribable_id] tuple,
      # build a map of { tuple => tracking_id }
      #
      # {
      #   [SponsorsTier,             42] => "MDEyOlNwb25zb3JzVGllcjEz",
      #   [SponsorsTier,             43] => "MDEyOlNwb25zb3JzVGllcjE0",
      #   [Marketplace::ListingPlan, 18] => "MDIyOk1hcmtldHBsYWNlTGlzdGluZ1BsYW4x",
      #   [SponsorsTier,             44] => "MDEyOlNwb25zb3JzVGllcjE1",
      #   ...
      # }
      decoded_map = tracking_ids.each_with_object({}) do |tracking_id, map|
        tuple = decode_tracking_id(tracking_id)
        map[tuple] = tracking_id
      end

      # Group the decoded map by class name and batch AR queries by class to look up
      # the subscribables.
      #
      # Return a hash of { tracking_id => subscribable }
      #
      # {
      #   "MDEyOlNwb25zb3JzVGllcjEz" => #<SponsorsTier id: 42, ...>,
      #   "MDEyOlNwb25zb3JzVGllcjE0" => #<SponsorsTier id: 43, ...>,
      #   "MDIyOk1hcmtldHBsYWNlTGlzdGluZ1BsYW4x" => #<Marketplace::ListingPlan id: 18, ...>,
      #   "MDEyOlNwb25zb3JzVGllcjE1" => #<SponsorsTier id: 99, ...>,
      # }
      lookups_by_class = decoded_map.keys.group_by(&:first)
      lookups_by_class.each_with_object({}) do |(klass, tuples), subscribable_map|
        next unless klass.respond_to?(:zuora_tracking_enabled?) && klass.zuora_tracking_enabled?
        ids = tuples.map(&:last)
        subscribables = klass.where(id: ids).includes_listings.index_by(&:id)
        subscribables.each do |id, subscribable|
          tuple = [klass, id]
          tracking_id = decoded_map[tuple]
          subscribable_map[tracking_id] = subscribable
        end
      end
    end

    # Public: batch lookup of subscribables from a list of zuora ProductRatePlanCharge IDs
    #
    # Returns Hash { String product_rpc_id => subscribable }
    sig do
      params(product_rpc_ids: T::Array[String])
        .returns(T::Hash[String, Billing::Types::Subscribable])
    end
    def self.from_product_rpc_ids(product_rpc_ids)
      return {} if product_rpc_ids.empty?

      # Zuora ProductRatePlanCharge IDs are stored as a serialized hash in Billing::ProductUUID
      where_clause = "zuora_product_rate_plan_charge_ids LIKE '%#{product_rpc_ids.join("%' OR zuora_product_rate_plan_charge_ids LIKE '%")}%'"
      ActiveRecord::Base.connected_to(role: :reading) do
        scope = Billing::ProductUUID.where(where_clause)
        listing_plan_id_map = scope.where(product_type: Marketplace::ListingPlan::ZuoraDependency::ZUORA_PRODUCT_TYPE).each_with_object({}) do |product, hash|
          product_rpc_id = product.zuora_product_rate_plan_charge_ids[:flat] || product.zuora_product_rate_plan_charge_ids[:unit]
          product_key = product.product_key
          hash[product_rpc_id] = product_key
        end
        listing_plans = Marketplace::ListingPlan.where(id: listing_plan_id_map.values)

        listing_plans = listing_plans.to_a
        listing_plan_id_map.each do |product_rpc_id, product_key|
          listing_plan_id_map[product_rpc_id] = listing_plans.find { |plan| plan.id == product_key.to_i }
        end
        listing_plan_id_map
      end
    end

    # Public: decode an encoded tracking ID into its class_name/ID components
    #
    # This tracking ID decoding implementation is borrowed from
    # Platform::Helpers::NodeIdentification.from_global_id.
    #
    # Returns an array of [Class, Integer ID]
    sig { params(tracking_id: String).returns(T::Array[T.any(T::Class[T.anything], Integer)]) }
    def self.decode_tracking_id(tracking_id)
      decoded_tracking_id = Base64.strict_decode64(tracking_id)
      length_string, rest = decoded_tracking_id.split(":", 2)
      rest = T.must(rest)
      length = length_string.to_i
      class_name, id = [rest[0..length - 1], rest[length..-1]]
      [class_name.to_s.constantize, id.to_i]
    end

    # Public: encode this subscribable's type/id to store as a Zuora custom field value
    #
    sig { returns(String) }
    def zuora_tracking_id
      T.bind(self, Billing::Types::Subscribable)

      subscribable_type = self.class.name.to_s
      components = ["0", subscribable_type.length, ":", subscribable_type, id]
      Base64.strict_encode64(components.join)
    end

    sig { returns(BigDecimal) }
    def monthly_price_in_dollars
      BigDecimal(monthly_price_in_cents.to_i.abs) / BigDecimal(100)
    end

    sig { returns(BigDecimal) }
    def yearly_price_in_dollars
      BigDecimal(yearly_price_in_cents.to_i.abs) / BigDecimal(100)
    end

    # Public: Returns the base price for this plan/tier.
    # Might be overriden by the model including this module.
    #
    # args - hash of arguments used to determine the base price of the subscribable.
    # args[:duration] - Optional. The duration price to return, :month or :year. Defaults to :month.
    #
    # Returns a Billing::Money
    sig { overridable.params(args: T.untyped).returns(Billing::Money) }
    def base_price(**args)
      duration = args[:duration].presence || :month
      Billing::Money.new \
        duration.to_sym == :month ? monthly_price_in_cents : yearly_price_in_cents
    end

    sig { params(account: T.nilable(User), quantity: Integer).returns(Billing::Money) }
    def prorated_total_price(account: nil, quantity: 1)
      T.bind(self, Billing::Types::Subscribable)
      return (base_price * quantity) unless account

      # Use Billing::Subscription to figure out how much to prorate
      subscription = ::Billing::Subscription.new(ends: account.billed_on)
      service_remaining = Rational(subscription.service_days_remaining, subscription.duration_in_days)
      service_remaining = 1 if service_remaining.zero?

      purpose = is_a?(SponsorsTier) && GitHub.sponsors_enabled? ? :sponsors : :general
      plan_subscription = account.plan_subscription_for(purpose) || Billing::PlanSubscription.new(
        user: account,
        purpose: purpose,
      )

      subscription_item = ::Billing::SubscriptionItem.new \
        subscribable_type: self.class.name,
        subscribable_id: self.id,
        quantity: quantity,
        plan_subscription: plan_subscription
      subscription_item.set_free_trial_ends_on

      Billing::Pricing.new(
        plan_duration: User::BillingDependency::MONTHLY_PLAN,
        subscription_item: subscription_item,
        service_remaining: service_remaining,
      ).discounted
    end

    # Public: Returns true if this is a paid plan/tier.
    sig { returns(T::Boolean) }
    def paid?
      T.bind(self, Billing::Types::Subscribable)

      monthly_price_in_cents != 0 || yearly_price_in_cents != 0
    end

    # Public: Returns true if the given User/Organization can purchase this plan/tier.
    sig { params(account: Billing::Types::Account).returns(T::Boolean) }
    def can_subscribe_with_account?(account)
      T.bind(self, Billing::Types::Subscribable)

      return false if for_organizations_only? && account.user?
      return false if for_users_only? && account.organization?

      true
    end

    sig { returns(T.nilable(String)) }
    def account_type_text
      return "personal accounts" if for_users_only?
      "organizations" if for_organizations_only?
    end

    # Public: Get a description of this subscribable for use on billing line items. Might be overridden by the
    # model including this module.
    #
    # args - Hash of arguments to help build the description of a line item using this subscribable; unused in this
    #        module but may be overridden by models that include this module
    #
    sig { overridable.params(args: T.untyped).returns(String) }
    def line_item_description(**args)
      "#{listing.name} - #{name}"
    end
  end
end
