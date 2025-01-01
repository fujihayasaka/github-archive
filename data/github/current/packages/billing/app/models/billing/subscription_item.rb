# typed: strict
# frozen_string_literal: true

module Billing
  class SubscriptionItem < ApplicationRecord::Domain::Users

    include GitHub::Memoizer

    include GitHub::Relay::GlobalIdentification
    include Billing::SubscriptionItem::MarketplaceDependency
    include Billing::SubscriptionItem::SponsorsDependency

    class UnprocessableError < StandardError; end
    class ForbiddenError < StandardError; end

    MARKETPLACE_SUBSCRIBABLE_TYPE = 0

    enum :subscribable_type, {
      Marketplace::ListingPlan.name => MARKETPLACE_SUBSCRIBABLE_TYPE,
      SponsorsTier.name => 1,
      Billing::ProductUUID.name => 2,
    }, prefix: :subscribable

    belongs_to :plan_subscription
    belongs_to :subscribable, polymorphic: true
    belongs_to :marketplace_listing_plan,
               class_name: "Marketplace::ListingPlan",
               foreign_key: :subscribable_id,
               inverse_of: :subscription_items
    belongs_to :product_uuid,
               foreign_key: :subscribable_id,
               inverse_of: :subscription_items
    belongs_to :sponsors_tier,
               foreign_key: :subscribable_id,
               inverse_of: :subscription_items
    belongs_to :organization

    has_one :customer, through: :plan_subscription
    has_one :integration_installation

    # An AppleSubscription record indicates the subscription item was purchased via and is being billed by Apple.
    has_one :apple_subscription,
      dependent: :destroy,
      inverse_of: :subscription_item

    # A GoogleSubscription record indicates the subscription item was purchased via and is being billed by Google.
    has_one :google_subscription,
      dependent: :destroy,
      inverse_of: :subscription_item

    scope :active, -> { where("quantity > 0") }
    scope :cancelled, -> { where(quantity: 0) }
    scope :latest_first, -> { order(id: :desc) }

    scope :free_trials, -> {
      where("free_trial_ends_on > ?", GitHub::Billing.today.to_formatted_s(:db))
    }

    scope :with_product_uuid_type, -> { where(subscribable_type: Billing::ProductUUID.name) }
    scope :without_product_uuid_type, -> { where.not(subscribable_type: Billing::ProductUUID.name) }
    scope :not_installed, -> { where(installed_at: nil) }
    scope :purchased_before, -> (time) { where("subscription_items.created_at < ?", time) }
    scope :purchased_between, -> (start_time, end_time) { where("subscription_items.created_at BETWEEN ? AND ?", start_time, end_time) }
    scope :purchased_since, -> (num_days) { where(created_at: num_days.days.ago..) }
    scope :for_account, ->(user_or_id) do
      joins(:plan_subscription).merge(Billing::PlanSubscription.for_user(user_or_id))
    end
    scope :for_enterprise, ->(customer_id) do
      joins(:plan_subscription).where(plan_subscription: { user: nil, customer_id: customer_id })
    end
    scope :for_plan_subscription, ->(plan_subscription) { where(plan_subscription_id: plan_subscription) }
    scope :for_organization, ->(organization) { where(organization_id: organization.id) }

    validates_presence_of :plan_subscription, on: :create
    validates :subscribable_id, :subscribable_type, presence: true
    validates :quantity, \
      presence: true,
      numericality: {
        only_integer: true,
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 100_000,
      }
    validate :valid_subscribable, on: :create, if: :subscribable
    validate :does_not_conflict_with_existing_subscriptions
    validate :valid_subscribable_for_account_type, on: :create, if: :subscribable
    validate :valid_subscribable_for_plan_subscription_purpose, if: :activating?
    validate :plan_subscription_exists_when_active, on: :update

    sig { returns(T.nilable(Public::InAppPurchase)) }
    def in_app_purchase
      if apple_in_app_purchase?
        Public::InAppPurchase.apple(original_transaction_id: T.must(apple_subscription).original_transaction_id)
      elsif google_in_app_purchase?
        Public::InAppPurchase.google(purchase_token: T.must(google_subscription).purchase_token)
      else
        nil
      end
    end

    sig { returns(T::Boolean) }
    def in_app_purchase?
      apple_in_app_purchase? || google_in_app_purchase?
    end

    sig { returns(T::Boolean) }
    def apple_in_app_purchase?
      async_apple_in_app_purchase?.sync
    end

    sig { returns(Promise[T::Boolean]) }
    def async_apple_in_app_purchase?
      async_apple_subscription.then do |apple_subscription|
        apple_subscription.present?
      end
    end

    sig { returns(T::Boolean) }
    def google_in_app_purchase?
      async_google_in_app_purchase?.sync
    end

    sig { returns(Promise[T::Boolean]) }
    def async_google_in_app_purchase?
      async_google_subscription.then do |google_subscription|
        google_subscription.present?
      end
    end

    sig { params(in_app_purchase: Public::InAppPurchase).void }
    def build_in_app_purchase_association(in_app_purchase)
      case in_app_purchase.type
      when Public::InAppPurchase::Type::Apple
        build_apple_subscription(original_transaction_id: in_app_purchase.identifier)
      when Public::InAppPurchase::Type::Google
        build_google_subscription(purchase_token: in_app_purchase.identifier)
      end
    end

    sig { void }
    def destroy_in_app_purchase_subscriptions!
      apple_subscription&.destroy!
      google_subscription&.destroy!
    end

    sig { returns T.nilable(Integer) }
    def monthly_price_in_cents
      subscribable&.monthly_price_in_cents
    end

    sig { returns T.nilable(Integer) }
    def yearly_price_in_cents
      subscribable&.yearly_price_in_cents
    end

    sig { returns T.nilable(T.any(Marketplace::Listing, SponsorsListing)) }
    def listing
      subscribable&.listing
    end

    sig { returns T.nilable(Integer) }
    def listing_id
      subscribable&.listing_id
    end

    sig { params(invoice_item: Billing::Zuora::InvoiceItem).returns(T::Boolean) }
    def matches_invoice_item?(invoice_item)
      return false unless subscribable
      subscribable.matches_invoice_item?(invoice_item)
    end

    delegate \
      :slug,
      :listable,
      to: :listing

    delegate \
      :name,
      to: :listing,
      allow_nil: true,
      prefix: true

    delegate \
      :external_subscription,
      :plan_duration,
      :user,
      to: :plan_subscription,
      allow_nil: true

    delegate :github_arr, to: :subscribable

    after_commit :synchronize_plan_subscription, unless: :skip_sync

    before_destroy :instrument_billable_product_removal
    after_destroy :delete_pending_changes
    after_update :delete_pending_changes, if: -> do
      T.bind(self, Billing::SubscriptionItem)

      cancelled? && product_uuid?
    end

    after_commit :downgrade_to_free_if_nothing_billed_on_free_with_addons_plan
    before_create :set_free_trial_ends_on
    after_commit :touch_integrate_installation

    attribute :skip_sync, :boolean, default: false

    sig { returns(T.nilable(T::Boolean)) }
    attr_accessor :is_installation_update_req

    sig { returns(T.nilable(IntegrationInstallation)) }
    attr_accessor :installation

    # Public: Get the total sum of the given subscription items' monthly price in cents.
    #
    # subscription_items - either an ActiveRecord::Relation or an Array of Billing::SubscriptionItem
    # include_fees - Boolean. Whether to include fees in the total price, if fees are
    #                applicable to the subscription item, such as for a sponsorship subscription item.
    sig do
      params(
        subscription_items: T.any(ActiveRecord::Relation, T::Array[Billing::SubscriptionItem]),
        include_fees: T::Boolean,
      ).returns(Promise[Integer])
    end
    def self.async_total_monthly_price_in_cents(subscription_items, include_fees:)
      if subscription_items.is_a?(ActiveRecord::Relation)
        cents_list = subscription_items.preload(:subscribable).map do |subscription_item|
          subscribable = subscription_item.subscribable
          base_price = if subscribable
            subscribable.base_price(subscription_item: subscription_item, include_fees: include_fees)
          else
            Billing::Money.zero
          end
          base_price.cents * subscription_item.quantity
        end
        Promise.resolve(cents_list.sum)
      else
        promises = subscription_items.map do |subscription_item|
          subscription_item.async_subscribable.then do |subscribable|
            base_price = if subscribable
              subscribable.base_price(subscription_item: subscription_item, include_fees: include_fees)
            else
              Billing::Money.zero
            end
            base_price.cents * subscription_item.quantity
          end
        end
        Promise.all(promises).then { |cents_list| cents_list.sum }
      end
    end

    sig { params(subscription_items: T.any(ActiveRecord::Relation, T::Array[Billing::SubscriptionItem]), include_fees: T::Boolean).returns(Integer) }
    def self.total_monthly_price_in_cents(subscription_items, include_fees:)
      async_total_monthly_price_in_cents(subscription_items, include_fees: include_fees).sync
    end

    sig { returns(Promise[T.nilable(::Billing::Types::Account)]) }
    def async_account
      async_plan_subscription.then do |plan_subscription|
        billable_entity_promise = plan_subscription&.async_billable_entity || Promise.resolve(nil)
        billable_entity_promise.then do |billable_entity|
          next billable_entity if billable_entity
          if subscribable_SponsorsTier?
            async_sponsorship.then do |sponsorship|
              sponsorship&.async_sponsor
            end
          end
        end
      end
    end

    sig { returns(T.nilable(::Billing::Types::Account)) }
    def account
      billable_entity = plan_subscription&.billable_entity
      return billable_entity if billable_entity
      if subscribable_SponsorsTier?
        sponsorship&.sponsor
      end
    end

    sig { returns(T::Boolean) }
    def listable_is_integration?
      return false unless listing
      listing.respond_to?(:listable_is_integration?) &&
        T.unsafe(listing).listable_is_integration?
    end

    sig do
      returns(
        Promise[
          T.nilable(T.any(SponsorsListing, Marketplace::Listing))
        ]
      )
    end
    def async_listing
      async_subscribable.then do |subscribable|
        subscribable.async_listing
      end
    end

    sig { returns(T.nilable(::Billing::BillingTransaction)) }
    def latest_billing_transaction
      latest_line_item&.billing_transaction
    end

    sig { params(start_date: Date).returns(T.nilable(::Billing::BillingTransaction)) }
    def active_billing_transaction(start_date: GitHub::Billing.today)
      latest_line_item = self.latest_line_item
      return nil if latest_line_item.nil?

      service_end_date = latest_line_item.service_end_date
      return latest_line_item.billing_transaction if service_end_date.blank?

      return nil if service_end_date.before?(start_date)

      latest_line_item.billing_transaction
    end

    sig { returns(T.nilable(::Billing::BillingTransaction::LineItem)) }
    memoize def latest_line_item
      Billing::BillingTransaction::LineItem
        .for_subscribable_and_user(subscribable, user.id)
        .select(:billing_transaction_id, :service_end_date)
        .last
    end

    # Public: Returns the subscription item's billing interval depending on the subscribable type.
    # (e.g. "monthly", "yearly")
    # ProductUUID subcription items always return the subscribable's billing cycle
    # Other subscription items return the plan subscription's plan duration
    batch_method :billing_interval do |sub_items|
      GitHub::PrefillAssociations.prefill_associations(sub_items, [:plan_subscription, :subscribable])

      interval_promises = sub_items.map do |sub_item|
        if sub_item.product_uuid?
          sub_item.async_subscribable.then do |subscribable|
            subscribable.billing_cycle
          end
        else
          sub_item.async_plan_subscription.then do |plan_subscription|
            sub_item.async_account.then do |account|
              next if account.nil?

              plan_subscription.async_plan_duration
            end
          end
        end
      end
      intervals = Promise.all(interval_promises).sync

      sub_items.zip(intervals).to_h
    end

    sig { returns(T::Boolean) }
    def monthly?
      billing_interval.to_s == "month"
    end

    sig { returns(T::Boolean) }
    def yearly?
      billing_interval.to_s == "year"
    end

    # Public: Get the cost of this subscription item.
    #
    # args - Hash of arguments used to determine the base price of the subscription item, with the following keys:
    #   :duration - The duration price to return, e.g., :month or :year; defaults to :month
    #
    # Returns a Billing::Money.
    sig { params(args: T.untyped).returns(::Billing::Money) }
    def base_price(**args)
      async_base_price(**args).sync
    end

    # Public: Get the cost of this subscription item.
    #
    # args - Hash of arguments used to determine the base price of the subscription item, with the following keys:
    #   :duration - The duration price to return, e.g., :month or :year; defaults to :month
    sig { params(args: T.untyped).returns(Promise[::Billing::Money]) }
    def async_base_price(**args)
      async_subscribable.then do |subscribable|
        next Billing::Money.zero unless subscribable
        subscribable.base_price(**args)
      end
    end

    # Public: Returns the total cost for this item.
    sig do
      params(
        duration: T.nilable(T.any(String, Symbol)),
        service_remaining: T.nilable(T.any(Integer, Float)),
        trial_price: T::Boolean,
        base_price_args: T.untyped
      ).returns(::Billing::Money)
    end
    def price(duration: nil, service_remaining: 1, trial_price: true, **base_price_args)
      async_price(duration: duration, service_remaining: service_remaining,
        trial_price: trial_price, **base_price_args).sync
    end

    sig do
      params(
        duration: T.nilable(T.any(String, Symbol)),
        service_remaining: T.nilable(T.any(Integer, Float)),
        trial_price: T::Boolean,
        base_price_args: T.untyped
      ).returns(Promise[::Billing::Money])
    end
    def async_price(duration: nil, service_remaining: 1, trial_price: true, **base_price_args)
      trial_price_promise = if trial_price
        async_use_free_trial_price?
      else
        Promise.resolve(false)
      end

      duration_promise = if duration
        Promise.resolve(duration)
      else
        if subscribable_Billing_ProductUUID?
          async_subscribable.then { |subscribable| subscribable&.billing_cycle }
        else
          async_plan_subscription.then { |plan_subscription| plan_subscription&.plan_duration }
        end
      end

      trial_price_promise.then do |use_free_trial_price|
        next Billing::Money.zero if use_free_trial_price

        duration_promise.then do |duration|
          duration ||= User::BillingDependency::MONTHLY_PLAN
          async_base_price(**base_price_args.merge(duration: duration)).then do |base_price|
            Billing::Money.new((base_price.cents * quantity * service_remaining).to_i)
          end
        end
      end
    end

    sig { returns(T::Boolean) }
    def past_service_period?
      next_billing_date <= GitHub::Billing.today
    end

    # These are all the available "rate" identifiers that can be associated with a product.
    # These product_rate_plan_charge_ids ultimately come from the Billing::ProductUUID table.
    sig { returns(T::Array[String]) }
    memoize def product_rate_plan_charge_ids
      if subscribable_Billing_ProductUUID?
        T.cast(subscribable, Billing::ProductUUID).charges.map { |c| c.zuora_product_rate_plan_charge_id }
      elsif subscribable_SponsorsTier?
        sponsors_rate_plan_charge_ids = subscribable.listing.zuora_rate_plan_charge_ids(billing_cycle: billing_interval.to_sym)
        # Sponsors should only have flat rate charges and fee charges
        sponsors_rate_plan_charge_ids.values
      else # Must be a Marketplace Listing Plan
        marketplace_charge_ids = subscribable.zuora_charge_ids(cycle: billing_interval.to_sym)
        marketplace_charge_ids.values
      end
    end

    # Returns the product rate plan charge id that currently has charges in the customer's Zuora subscription.
    sig { returns(T.nilable(String)) }
    def active_product_rate_plan_charge_id
      plan_subscription = T.must(self.plan_subscription)

      # First check if the charges are in our local cache
      active_product_rate_plan_charge_id = product_rate_plan_charge_ids.find do |prp_charge_id|
        plan_subscription.zuora_rate_plan_charges[prp_charge_id].present? &&
          !!plan_subscription.zuora_rate_plan_charges[prp_charge_id]&.has_key?(:charged_through_date)
      end

      return active_product_rate_plan_charge_id if active_product_rate_plan_charge_id.present?
      return unless external_subscription.present?

      # If we have an external subscription, update the cache just in case. These are cases
      # where synchronization hasn't completed but the subscription has been created.
      # In those cases the synchronization will take care of re-updating the cache anyway
      #
      # TODO:
      # 1. fetch the cache
      # 2. perform the update of the cache
      # 3. run an experiment to see if there's a difference between the two instances
      # If there's no difference, we can remove the updating of the cache and the checking of external_subscription
      ActiveRecord::Base.connected_to(role: :writing) do
        plan_subscription.update_from_zuora_subscription(zuora_subscription_object: external_subscription)
      end

      product_rate_plan_charge_ids.find do |prp_charge_id|
        plan_subscription.zuora_rate_plan_charges[prp_charge_id].present? &&
          !!plan_subscription.zuora_rate_plan_charges[prp_charge_id]&.has_key?(:charged_through_date)
      end
    end

    sig { returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def active_product_rate_plan_charges
      plan_subscription = T.must(self.plan_subscription)
      active_prp_charge_id = active_product_rate_plan_charge_id

      return if active_prp_charge_id.nil? || plan_subscription.zuora_rate_plan_charges.nil?

      plan_subscription.zuora_rate_plan_charges[active_prp_charge_id]
    end

    sig { returns(Date) }
    def next_billing_date
      return (external_subscription&.next_billing_date || GitHub::Billing.today) unless product_uuid?

      if on_free_trial?
        free_trial_ends_on + 1.day
      else
        charged_through_date = active_product_rate_plan_charges&.dig(:charged_through_date)
        charged_through_date || GitHub::Billing.today
      end
    end

    # Public: Returns whether the subscription item disqualifies the free trial on the subscribable
    # TODO write a similar method for productUUID subscribables
    sig { returns(T::Boolean) }
    def disqualifies_for_free_trial?
      paid? || on_free_trial?
    end

    # Public: Checks if the subscription item is currently on a free trial
    sig { returns(T::Boolean) }
    def on_free_trial?
      # The free trial ends at the *end* of the free_trial_ends_on day/date
      free_trial_ends_on = self.free_trial_ends_on
      !!(free_trial_ends_on.present? && GitHub::Billing.future?(free_trial_ends_on + 1.day))
    end

    # Public: Checks if the given user can administer the subscription item, such as cancelling
    # or editing it.
    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def adminable_by?(user)
      async_adminable_by?(user).sync
    end

    sig { params(user: T.nilable(User)).returns(Promise[T::Boolean]) }
    def async_adminable_by?(user)
      async_account.then do |account|
        if account
          account.subscription_items_adminable_by?(user, subscribable_type: subscribable_type)
        else
          false
        end
      end
    end

    sig { returns(T::Boolean) }
    def cancelled?
      quantity.zero?
    end

    sig { returns(T::Boolean) }
    def pending_cancellation?
      return false unless pending_item_change = pending_subscription_item_change
      !!pending_item_change.cancellation?
    end

    # Public: Checks if this item is in a state that should be billed.
    sig { returns(T::Boolean) }
    def billable?
      return false if stale_one_time_sponsorship?
      if product_uuid?
        quantity > 0 && paid?
      else
        quantity > 0 && paid? && listing.present? && T.must(listing).billable?
      end
    end

    sig { returns(T::Boolean) }
    def paid?
      !!(subscribable&.paid? && !on_free_trial?)
    end
    alias :account_has_been_charged? :paid?

    sig { returns T::Boolean }
    def subscribable_paid?
      !!subscribable&.paid?
    end

    sig { returns(T.nilable(String)) }
    def subscribable_name
      subscribable&.name
    end

    sig { returns(String) }
    def subscription_summary
      subscribable.line_item_description
    end

    sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
    def async_viewable_by?(viewer)
      async_plan_subscription.then do |plan_subscription|
        T.must(plan_subscription).async_billable_entity.then do |owner|
          if owner.present? && owner.business? && owner.adminable_by?(viewer) && (owner.organizations & viewer&.owned_organizations).present?
            true
          elsif owner.present? && owner.id == viewer.try(:id)
            true
          elsif viewer.try(:site_admin?)
            true
          elsif owner.present? && owner.organization? && T.cast(owner, Organization).billing_manager?(viewer)
            true
          elsif viewer && owner.present? && viewer.owned_organizations.include?(owner)
            true
          else
            async_subscribable.then do |subscribable|
              subscribable.async_listing.then do |_listing|
                subscribable.adminable_by?(viewer)
              end
            end
          end
        end
      end
    end

    class MissingPlanSubscription < StandardError; end

    # Public: Schedule a cancellation for the subscription item
    #
    # actor                - The user requesting the cancellation.
    # force                - Cancel the item immediately.
    # skip_sync            - Don't immediately send sync to Zuora.
    # allow_cancelling_iap - Apple is the source-of-truth for in-app purchases, so we do not
    #                        want to cancel them by default. You can override this by passing in
    #                        true and acknowledging this but it is not recommended given the user
    #                        must now be directed to cancel their subscription in-app.
    #
    # Returns Billing::Public::SubscriptionItems::ResultStruct
    sig do
      params(
        force: T::Boolean,
        skip_sync: T::Boolean,
        actor: T.nilable(User),
        allow_cancelling_iap: T::Boolean
      ).returns(Billing::Public::SubscriptionItems::ResultStruct)
    end
    def cancel!(force: false, skip_sync: false, actor: nil, allow_cancelling_iap: false)
      account = self.account
      actor ||= account if account.is_a?(User)
      Failbot.push("gh.billing.subscription_item.id": id, "gh.organization.id": organization&.id,
        "gh.actor.id": actor&.id, "gh.account.type": account ? account.class.name : nil, "gh.account.id": account&.id)

      if cancelled?
        # The subscription item is already cancelled, so we don't need to do anything.
        Billing::Public::SubscriptionItems::ResultStruct.new(
          subscription_item: self,
          result: Billing::Public::ResultStruct.new(
            success: true,
            errors: [],
          ),
        )
      elsif one_time_sponsorship?
        # one-time sponsorships are deactivated on payment under normal circumstances,
        # but can be cancelled via stafftools if that deactivation fails for any reason.
        # In the direct cancellation case, we want to skip the subscription item updater
        # so the deactivation takes effect immediately.
        success = deactivate_without_callbacks
        Billing::Public::SubscriptionItems::ResultStruct.new(
          subscription_item: self,
          result: Billing::Public::ResultStruct.new(
            success:,
            errors: success ? [] : ["Error deactivating one-time sponsorship"],
          ),
        )
      else
        plan_subscription = self.plan_subscription
        raise MissingPlanSubscription unless plan_subscription
        ::Billing::SubscriptionItemUpdater.perform(
          force:,
          subscribable:,
          quantity: 0,
          sender: actor,
          plan_subscription:,
          skip_sync:,
          organization:,
          allow_cancelling_iap:
        )
      end
    end

    # Public: Schedule a background job to cancel and prorate refund a subscription item
    sig do
      params(
        organization: T.nilable(Organization),
        full_refund: T::Boolean,
        allow_cancelling_iap: T::Boolean
      ).returns(T::Boolean)
    end
    def cancel_and_refund!(organization: nil, full_refund: false, allow_cancelling_iap: false)
      !!Billing::CancelAndRefundSubscriptionItemJob.perform_later(
        self,
        organization_id: organization&.id,
        full_refund:,
        allow_cancelling_iap:
      )
    end

    # Public: Reactivate a cancelled subscription item
    #
    # actor                - The user requesting the reactivation.
    # quantity             - The quantity to reactivate.
    # start_free_trial     - Whether to start a free trial on reactivation
    # skip_sync            - Don't immediately send sync to Zuora.
    #
    # Returns Billing::Public::SubscriptionItems::ResultStruct
    sig do
      params(
        quantity: Integer,
        free_trial_length: ActiveSupport::Duration,
        skip_sync: T::Boolean,
        actor: T.nilable(User)
      ).returns(Billing::Public::SubscriptionItems::ResultStruct)
    end
    def reactivate!(quantity: 1, free_trial_length: 0.days, skip_sync: false, actor: nil)
      account = self.account
      actor ||= account if account.is_a?(User)
      Failbot.push("gh.billing.subscription_item.id": id, "gh.organization.id": organization&.id,
        "gh.actor.id": actor&.id, "gh.account.type": account ? account.class.name : nil, "gh.account.id": account&.id)

      if one_time_sponsorship?
        Billing::Public::SubscriptionItems::ResultStruct.new(
          subscription_item: self,
          result: Billing::Public::ResultStruct.new(
            success: false,
            errors: ["Cannot reactivate one-time sponsorship"],
          ),
        )
      else
        plan_subscription = self.plan_subscription
        raise MissingPlanSubscription unless plan_subscription

        ::Billing::SubscriptionItemUpdater.perform(
          force: false,
          subscribable:,
          quantity:,
          sender: actor,
          plan_subscription:,
          skip_sync:,
          organization:,
          start_free_trial: free_trial_length.positive?,
          free_trial_ends_on: free_trial_length.positive? ? free_trial_length.from_now.to_date : nil,
          include_inactive: true
        )
      end
    end

    # Public: Extends a trial to at most 60 days from today.
    # Returns a GitHub::Result object that can either contain an error or the subscription item
    sig { params(actor: User, days: Integer, is_stafftools_action: T::Boolean).returns(GitHub::Result) }
    def extend_trial!(actor:, days:, is_stafftools_action: false)
      return GitHub::Result.error(UnprocessableError.new("Cannot extend trial when trial is not active.")) unless on_free_trial?
      free_trial_ends_on = self.free_trial_ends_on

      return GitHub::Result.error(UnprocessableError.new("Days should be > 0 if extending a trial.")) unless days > 0
      return GitHub::Result.error(UnprocessableError.new("Trial extension should be <= 60 days from today.")) unless T.cast((free_trial_ends_on + days.days - Date.today), Rational).to_i <= 60
      unless account&.subscription_items_adminable_by?(actor, subscribable_type: subscribable.class.name, is_stafftools_action: is_stafftools_action)
        return GitHub::Result.error(ForbiddenError.new("#{actor} does not have permission to manage this account (#{account})"))
      end

      new_trial_end_date = free_trial_ends_on + days.days
      result = GitHub::Result.error(UnprocessableError.new("No pending change found."))
      Billing::SubscriptionItem.transaction do
        change = pending_subscription_item_change
        if change.present? && change.pending_plan_change.present?
          self.update!(free_trial_ends_on: new_trial_end_date)
          # also update active_on for pending plan change
          Billing::PendingPlanChange.transaction do
            change.pending_plan_change.update!(
              active_on: new_trial_end_date + 1.day,
            )
            result = GitHub::Result.new { self.reload }
          end
        end
      end
      result
    rescue ActiveRecord::ActiveRecordError => e
      Failbot.report(e,
      {
        :catalog_service => "github/ghas_self_serve_trial",
        "gh.account.id" => account&.id,
        "gh.account.type" => account.class.name,
        "gh.billing.subscription_item.id" => id
      })
      GitHub::Result.error(UnprocessableError.new("Failed to extend trial. Reason: #{e.class.name} #{e.message}"))
    end

    # Public: Ends a free trial immediately. If purchase_subscription is true, it will also keep the subscription and attempt
    #         to bill the customer.
    # Returns a GitHub::Result object that can either contain an error or the subscription item
    sig do
      params(
        actor: User,
        purchase_subscription: T::Boolean,
        seats: Integer,
        is_stafftools_action: T::Boolean,
        skip_sync: T::Boolean,
      ).returns(GitHub::Result)
    end
    def end_free_trial_now!(actor:, purchase_subscription:, seats: 0, is_stafftools_action: false, skip_sync: false)
      return GitHub::Result.error(UnprocessableError.new("Cannot end trial when trial is not active.")) unless on_free_trial?
      return GitHub::Result.error(UnprocessableError.new("Seats should be > 0 if purchasing subscription.")) if purchase_subscription && seats <= 0
      unless account&.subscription_items_adminable_by?(actor, subscribable_type: subscribable.class.name, is_stafftools_action: is_stafftools_action)
        return GitHub::Result.error(ForbiddenError.new("#{actor} does not have permission to manage this account (#{account})"))
      end

      seats = 0 unless purchase_subscription
      change = pending_subscription_item_change

      # If the pending plan change is missing (sometimes via stafftools), it should be safe to call SubscriptionItemUpdater
      if !change
        update = Billing::SubscriptionItemUpdater.perform(
          force: true,
          subscribable: subscribable,
          quantity: seats,
          sender: actor,
          end_free_trial: true,
          plan_subscription: T.must(plan_subscription),
          skip_sync: skip_sync || !purchase_subscription,
        )
        if update.result.success
          return GitHub::Result.new { self.reload }
        end
        raise Billing::Public::BillingError.new("Subscription item did not update with errors: #{update.result.errors.join(", ")}")
      end

      # otherwise update the pending plan change and run it
      result = GitHub::Result.error(UnprocessableError.new("No pending change found."))
      Billing::PendingSubscriptionItemChange.transaction do
        if change.present? && change.pending_plan_change.present?
          change.update!(
            quantity: seats
          )
          Billing::PendingPlanChange.transaction do
            change.pending_plan_change.update!(
              active_on: GitHub::Billing.today
            )
            ended_trial = change.pending_plan_change.run(skip_sync: skip_sync)
            # avoid raising ActiveRecord::Rollback, since we want the parent transaction to rollback too
            raise Billing::Public::BillingError.new("Failed to run pending plan change.") unless ended_trial
            result = GitHub::Result.new { self.reload }
          end
        end
      end
      result
    rescue ActiveRecord::ActiveRecordError, Billing::Public::BillingError, ::Platform::Errors::Unprocessable => e
      Failbot.report(e,
      {
        :catalog_service => "github/ghas_self_serve_trial",
        "gh.account.id" => account&.id,
        "gh.account.type" => account&.class&.name,
        "gh.billing.subscription_item.id" => id
      })
      if e.is_a?(ActiveRecord::ActiveRecordError)
        GitHub::Result.error(UnprocessableError.new("Failed to end trial. Reason: #{e.class.name} #{e.message}"))
      else
        GitHub::Result.error(e)
      end
    end

    # Public: deactivate subscription item without triggering all the callbacks
    sig { returns(T::Boolean) }
    def deactivate_without_callbacks
      update_columns(quantity: 0)
    end

    sig { returns(Promise[T.nilable(Billing::PendingSubscriptionItemChange)]) }
    def async_pending_subscription_item_change
      async_account.then do |account|
        next unless account

        async_subscribable.then do |subscribable|
          next unless subscribable

          if subscribable.respond_to?(:async_pending_subscription_item_change)
            if subscribable.try(:management_delegated_to_org?, account)
              org = async_organization.then do |organization|
                organization
              end
              subscribable.async_pending_subscription_item_change(account: account, organization: org.sync)
            else
              subscribable.async_pending_subscription_item_change(account: account)
            end
          else
            if subscribable.try(:management_delegated_to_org?, account)
              subscribable.pending_subscription_item_change(account: account, organization: organization)
            else
              subscribable.pending_subscription_item_change(account: account)
            end
          end
        end
      end
    end

    batch_method :pending_subscription_item_change do |sub_items|
      next if sub_items.empty?
      change_promises = sub_items.map do |sub_item|
        sub_item.async_pending_subscription_item_change.then do |change|
          change
        end
      end
      changes = Promise.all(change_promises).sync

      sub_items.zip(changes).to_h
    end

    sig { returns(ActiveRecord::AssociationRelation) }
    def pending_subscription_item_changes_for_product
      raise NotImplementedError, "pending_subscription_item_changes_for_product is not implemented for #{subscribable_type}" unless product_uuid?

      T.must(account)
        .pending_subscription_item_changes
        .for_product_type_product_uuid_subscribable(subscribable)
    end

    sig { returns(T::Boolean) }
    def active?
      quantity.to_i > 0
    end

    sig { returns(T.nilable(Date)) }
    def set_free_trial_ends_on
      if self.free_trial_ends_on.blank? && eligible_for_free_trial?(excluded_item: self)
        self.free_trial_ends_on = GitHub::Billing.today + ::Billing::Subscription::FREE_TRIAL_LENGTH
      end
    end

    sig { params(excluded_item: T.nilable(Billing::SubscriptionItem)).returns(T::Boolean) }
    def eligible_for_free_trial?(excluded_item: nil)
      async_eligible_for_free_trial?(excluded_item: excluded_item).sync
    end

    sig { params(excluded_item: T.nilable(Billing::SubscriptionItem)).returns(Promise[T::Boolean]) }
    def async_eligible_for_free_trial?(excluded_item: nil)
      async_subscribable.then do |subscribable|
        next false unless subscribable.has_free_trial?

        Promise.all([async_account, subscribable.async_listing]).then do |account, listing|
          account_is_eligible_for_trial(account, listing, excluded_item)
        end
      end
    end

    sig { params(installation: IntegrationInstallation).returns(T::Boolean) }
    def update_integrate_installation(installation)
      self.is_installation_update_req = true
      self.installation = installation
      !!touch_integrate_installation
    end

    sig { returns(T.nilable(Integer)) }
    def pending_change_id
      async_pending_change_id.sync
    end

    sig { returns(Promise[T.nilable(Integer)]) }
    def async_pending_change_id
      async_pending_subscription_item_change.then do |pending_subscription_item_change|
        next nil unless pending_subscription_item_change
        pending_subscription_item_change.async_pending_plan_change.then do |plan_change|
          plan_change&.id
        end
      end
    end

    sig { returns(T.nilable(Billing::Money)) }
    def post_trial_prorated_price
      async_post_trial_prorated_price.sync
    end

    sig { returns(Promise[T.nilable(Billing::Money)]) }
    def async_post_trial_prorated_price
      async_pending_subscription_item_change.then do |pending_subscription_item_change|
        pending_subscription_item_change&.price
      end
    end

    sig { returns(T::Boolean) }
    def has_pending_cycle_change?
      async_has_pending_cycle_change?.sync
    end

    sig { returns(Promise[T::Boolean]) }
    def async_has_pending_cycle_change?
      async_account.then do |account|
        next false unless account

        if account.is_a?(Business)
          account = T.must(account.customer)
        end

        account.async_pending_cycle_change.then do |pending_cycle_change|
          next false unless pending_cycle_change
          account.async_pending_subscription_item_changes.then do |change_list|
            next false if change_list.empty?
            Promise.all(change_list.map(&:async_listing)).then do |change_listings|
              next false if change_listings.blank?

              self.async_subscribable.then do |subscribable|
                subscribable.async_listing.then do |listing|
                  change_listings.include?(listing)
                end
              end
            end
          end
        end
      end
    end

    # Public: Is this subscription item allowed to be active at the same time as a subscription item for the given
    # subscribable?
    #
    # other_subscribable - a Billing::Subscribable, like a SponsorsTier or a Marketplace::ListingPlan
    sig { params(other_subscribable: T.nilable(Billing::Subscribable)).returns(T::Boolean) }
    def can_be_concurrent_with_subscription_item_for?(other_subscribable)
      # If this subscription item doesn't have a subscribable, no worries:
      return true unless subscribable

      # If this subscription item has been cancelled, no worries about activating a different one:
      return true unless active?

      # Consult this subscription item's subscribable, which will know if having multiple concurrent subscriptions
      # is allowed:
      subscribable.can_be_concurrent_with_subscription_item_for?(other_subscribable)
    end

    # Public: Checks for sdn_disabled for the subscribable item to check
    # before taking action on the item such as display the sponsors listing
    # SDN - Special Designated Nationals
    sig { returns(T::Boolean) }
    def sdn_disabled?
      return false unless subscribable&.respond_to?(:sdn_disabled?)
      subscribable.sdn_disabled?
    end

    sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
    def authorization_required?(viewer)
      async_authorization_required?(viewer).sync
    end

    sig { params(viewer: T.nilable(User)).returns(Promise[T::Boolean]) }
    def async_authorization_required?(viewer)
      @authorization_required_by_viewer ||= T.let(
        Hash.new do |hash, user|
          hash[user] = async_subscribable.then do |subscribable|
            subscribable.async_listing.then do |listing|
              async_account.then do |account|
                listing.async_listable.then do |listable|
                  if listing.respond_to?(:listable_is_oauth_application?) && listing.listable_is_oauth_application?
                    user.present? && user.oauth_authorizations.where(application_id: listing.listable_id).empty?
                  elsif listing.respond_to?(:listable_is_integration?) && listing.listable_is_integration?
                    !listable.installed_on?(account)
                  elsif subscribable_SponsorsTier?
                    true # TODO: what should the logic be here?
                  end
                end
              end
            end
          end
        end, T.nilable(T::Hash[T.nilable(User), Promise[T::Boolean]])
      )

      @authorization_required_by_viewer[viewer]
    end

    ## TODO: MARKETPLACE SPECIFIC
    sig { returns(T.nilable(String)) }
    def formatted_total_price
      async_formatted_total_price.sync
    end

    sig { returns(Promise[T.nilable(String)]) }
    def async_formatted_total_price
      async_subscribable.then do |subscribable|
        async_plan_subscription.then do |plan_subscription|
          T.must(plan_subscription).async_billable_entity.then do |owner|
            Pricing.new(
              plan_duration: owner.plan_duration,
              subscription_item: SubscriptionItem.new(subscribable: subscribable, quantity: quantity),
            ).marketplace_item_cost.format
          end
        end
      end
    end

    sig { returns(T::Boolean) }
    def product_uuid?
      subscribable_Billing_ProductUUID?
    end

    sig { params(other_subscribable: T.nilable(::Billing::Types::Subscribable)).returns(Promise[T::Boolean]) }
    def async_subscribable_for_same_listing?(other_subscribable)
      unless other_subscribable.class.name == subscribable_type
        # If we're changing from, say, a Marketplace plan to a Sponsors tier, they can't be for the same listing:
        return Promise.resolve(T.let(false, T::Boolean))
      end
      if T.must(other_subscribable).id == subscribable_id
        # Can avoid loading the subscribable relation to check its listing if we're given the exact same subscribable:
        return Promise.resolve(T.let(true, T::Boolean))
      end
      async_subscribable.then do |this_subscribable|
        this_subscribable.same_listing?(other_subscribable)
      end
    end

    # Public: Determine who a sponsorship or Marketplace listing is managed by, even if a business pays for it.
    sig { returns(T.nilable(T.any(User, Organization))) }
    def managing_entity
      return organization if organization
      return T.cast(account, Organization) if account&.organization?
      return T.cast(account, User) if account&.user?
      nil
    end

    sig { override.void }
    def reset_memoized_attributes
      remove_instance_variable(:@sponsorship_id) if defined?(@sponsorship_id)
      remove_instance_variable(:@authorization_required_by_viewer) if defined?(@authorization_required_by_viewer)
    end

    private

    sig { void }
    def plan_subscription_exists_when_active
      return if cancelled? || plan_subscription
      errors.add(:plan_subscription, "can't be blank")
    end

    sig { returns(Promise[T::Boolean]) }
    def async_use_free_trial_price?
      async_subscribable.then do |subscribable|
        next false unless subscribable&.has_free_trial?

        async_eligible_for_free_trial?.then do |eligible_for_free_trial|
          eligible_for_free_trial || on_free_trial?
        end
      end
    end

    # Internal: Ensure a valid subscribable is present
    sig { void }
    def valid_subscribable
      return if subscribable.available_for_purchase?
      errors.add(:base, "can't have a retired listing plan")
    end

    # Internal: Ensure that we only allow one `Billing::PlanSubscription` per `Marketplace::Listing` or per
    # `SponsorsListing`, except in the cases where multiple active subscriptions are allowed for a listing, such as
    # with one-time sponsorships.
    sig { void }
    def does_not_conflict_with_existing_subscriptions
      return unless active? && subscribable

      if product_uuid?
        other_subscription_items = T.must(plan_subscription).active_subscription_items.reload
          .where(subscribable_type: subscribable_type)
        other_subscription_items = other_subscription_items.where.not(id: id) if persisted?

        other_subscription_items.each do |other_subscription_item|
          errors.add(:base, "already has an active subscription for #{other_subscription_item.subscribable_name}") if other_subscription_item.subscribable_name == subscribable.name
        end
      else
        competing_subscription_items = other_active_subscription_items_for_listing(
          subscribable_type: subscribable.class.name,
          listing_id: subscribable.listing_id,
          organization_id: organization&.id
        )

        competing_subscription_items.each do |other_subscription_item|
          unless other_subscription_item.can_be_concurrent_with_subscription_item_for?(subscribable)
            errors.add(:base, "already has an active subscription for #{other_subscription_item.subscribable_name}")
          end
        end
      end
    end

    # Private: Find other subscription items using the specified subscribable type that are for the specified listing.
    #
    # subscribable_type - String like "SponsorsTier" or "Marketplace::ListingPlan"
    # listing_id - ID for a Billing::Subscribable's listing, such as a Marketplace::Listing ID or a SponsorsListing ID
    sig do
      params(subscribable_type: String, listing_id: Integer, organization_id: T.nilable(Integer))
        .returns(T::Array[Billing::SubscriptionItem])
    end
    def other_active_subscription_items_for_listing(subscribable_type:, listing_id:, organization_id: nil)
      return [] unless plan_subscription = self.plan_subscription

      # See https://github.com/github/sponsors/issues/1909 for details on why reloading is necessary here.
      other_subscription_items = plan_subscription.active_subscription_items.reload
        .where(subscribable_type: subscribable_type)
        .where(organization_id: organization_id)
        .includes(:subscribable) # preload subscribable since we get listing_id off of it
      other_subscription_items = other_subscription_items.where.not(id: id) if persisted?
      other_subscription_items.select { |sub_item| sub_item.listing_id == listing_id }
    end

    # Internal: Queues up a SynchronizePlanSubscription job for the user that
    # owns the PlanSubscription this item belongs to.
    sig { void }
    def synchronize_plan_subscription
      if plan_subscription = self.plan_subscription
        plan_subscription.synchronize_later
      end
    end

    # Private: Cleans up all pending subscription item change records for this subscription item's charge
    sig { void }
    def delete_pending_changes
      return unless user

      if subscribable_Marketplace_ListingPlan?
        user.pending_subscription_item_changes.for_marketplace_listing(listing).destroy_all
      # If there is a free trial active, we'd only want to cancel the specific subscribable associated to the free trial
      elsif subscribable_Billing_ProductUUID? && !on_free_trial?
        user.pending_subscription_item_changes.for_product_type_product_uuid_subscribable(subscribable).destroy_all
      else
        user.pending_subscription_item_changes.where(subscribable: subscribable).destroy_all
      end
    end

    sig { void }
    def valid_subscribable_for_account_type
      return unless account

      unless subscribable.can_subscribe_with_account?(account)
        errors.add(:base, "This plan is for #{subscribable.account_type_text} only, please select a different billing account or plan.")
      end
    end

    sig { void }
    def valid_subscribable_for_plan_subscription_purpose
      return unless plan_subscription = self.plan_subscription

      if subscribable_SponsorsTier? && !plan_subscription.sponsors_purpose?
        errors.add(:subscribable, "Sponsorships can only be added to the sponsors-purpose subscription, please " \
          "select a different plan subscription.")
      elsif !subscribable_SponsorsTier? && plan_subscription.sponsors_purpose?
        errors.add(:subscribable, "Only sponsorships can be added to the sponsors-purpose subscription, please " \
          "select a different plan subscription.")
      end
    end

    sig do
      params(
        account: T.nilable(::Billing::Types::Account),
        listing: T.any(::Billing::ProductUUID, ::Marketplace::Listing, ::SponsorsTier),
        excluded_item: T.nilable(::Billing::SubscriptionItem)
      ).returns(T::Boolean)
    end
    def account_is_eligible_for_trial(account, listing, excluded_item)
      # if account is nil this is only a hypothetical item being checked on
      # order preview. This means it's automatically eligible, since the user
      # has never had an item on this listing.
      if account.nil?
        true
      else
        account.eligible_for_free_trial_on?(product: listing, excluded_subscription_item: excluded_item)
      end
    end

    sig { void }
    def instrument_billable_product_removal
      GlobalInstrumenter.instrument(
        "billing.subscription_item_change",
        actor_id: GitHub.context[:actor_id],
        user_id: plan_subscription&.user_id,
        old_subscribable: subscribable,
        old_quantity: quantity,
      )
    end

    sig { void }
    def downgrade_to_free_if_nothing_billed_on_free_with_addons_plan
      account = self.account
      return if account.nil?
      return if !destroyed? && active?

      account.update_plan_if_addons_changed unless account.is_a?(Business)
    end

    # it is required to update subscription_item in integration_installation whenever we update the subscription
    # before this, it remain linked to cancelled subscription item only
    sig { returns(T.nilable(T::Boolean)) }
    def touch_integrate_installation
      return if !is_installation_update_req
      if installation = self.installation
        installation.update(subscription_item_id: id)
      end
    end

    sig { returns(T::Boolean) }
    def activating?
      return false unless quantity.to_i.positive?

      new_record? || quantity_changed? && quantity_was == 0
    end
  end
end
