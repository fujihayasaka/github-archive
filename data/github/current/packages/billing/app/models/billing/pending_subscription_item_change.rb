# typed: strict
# frozen_string_literal: true

module Billing
  class PendingSubscriptionItemChange < ApplicationRecord::Domain::Integrations
    include Instrumentation::Model

    after_create_commit :instrument_creation
    after_destroy_commit :instrument_destroy

    enum :subscribable_type, {
      Marketplace::ListingPlan.name => 0,
      SponsorsTier.name => 1,
      Billing::ProductUUID.name => 2
    }, prefix: :subscribable

    belongs_to :pending_plan_change, class_name: "Billing::PendingPlanChange"
    belongs_to :subscribable, polymorphic: true
    belongs_to :plan_subscription
    belongs_to :organization

    validates :plan_subscription, presence: true, on: :create
    validate :plan_subscription_belongs_to_a_billable_entity, if: :plan_subscription

    delegate :name, to: :listing, prefix: true, allow_nil: true

    delegate :name, to: :subscribable, prefix: :product, allow_nil: true

    delegate :business, to: :customer, allow_nil: true

    delegate :is_complete?, to: :pending_plan_change

    sig { returns(T.any(User, Organization, Business)) }
    def billable_entity
      user || business
    end

    sig { returns(T.nilable(T.any(Marketplace::Listing, SponsorsListing))) }
    def listing
      async_listing.sync
    end

    sig { returns(Promise[T.nilable(T.any(Marketplace::Listing, SponsorsListing))]) }
    def async_listing
      async_subscribable.then do |subscribable|
        subscribable.async_listing
      end
    end

    scope :joins_marketplace_listing_plans, -> {
      join_sql = <<-SQL
        INNER JOIN marketplace_listing_plans
        ON (marketplace_listing_plans.id = pending_subscription_item_changes.subscribable_id
        AND pending_subscription_item_changes.subscribable_type = #{subscribable_types[Marketplace::ListingPlan.name.to_s]})
      SQL

      joins(join_sql)
    }

    scope :joins_marketplace_listings, -> {
      joins_marketplace_listing_plans.
        joins("JOIN marketplace_listings on marketplace_listings.id = marketplace_listing_plans.marketplace_listing_id")
    }

    scope :for_product_uuid_subscribable, -> (product_uuid) {
      uuid_ids = Billing::ProductUUID.where(
        product_key: product_uuid.product_key,
        product_type: product_uuid.product_type,
      ).pluck(:id)

      where(subscribable_type: Billing::ProductUUID.name, subscribable_id: uuid_ids)
    }

    scope :for_product_type_product_uuid_subscribable, -> (product_uuid) {
      uuid_ids = Billing::ProductUUID.where(
        product_type: product_uuid.product_type,
      ).pluck(:id)

      where(subscribable_type: Billing::ProductUUID.name, subscribable_id: uuid_ids)
    }

    scope :for_marketplace_listing_plan, -> (plan) do
      joins_marketplace_listing_plans.where(marketplace_listing_plans: { id: plan.id })
    end

    scope :for_marketplace_listing_slug, ->(listing_slug) do
      joins_marketplace_listings.where(marketplace_listings: { slug: listing_slug })
    end

    scope :for_subscribable_listing, -> (listing) do
      if listing.is_a?(Marketplace::Listing)
        pending_changes = for_marketplace_listing(listing.id)
      elsif listing.is_a?(SponsorsListing)
        pending_changes = for_sponsors_listing(listing)
      end

      pending_changes
    end

    scope :for_organization, -> (organization) { where(organization_id: organization&.id) }

    scope :for_plan_subscription, -> (plan_subscription) do
      user_ids, customer_ids = Billing::PlanSubscription.general_purpose.where(id: plan_subscription).pick(:user_id, :customer_id)

      if user_ids.present? || customer_ids.present?
        condition = "pending_subscription_item_changes.plan_subscription_id = ? OR pending_plan_changes.user_id = ? OR pending_plan_changes.customer_id = ?"
        joins(:pending_plan_change)
          .where(condition, plan_subscription, user_ids, customer_ids)
      else
        where(plan_subscription_id: plan_subscription)
      end
    end

    scope :for_marketplace_listing, -> (listing_id) do
      joins_marketplace_listing_plans.where(marketplace_listing_plans: { marketplace_listing_id: listing_id })
    end

    scope :for_sponsors_listing, -> (listing) do
      sponsors_tiers = if listing.is_a?(SponsorsListing)
        listing.sponsors_tiers
      else # assume we were given a listing ID
        SponsorsTier.for_listing(listing)
      end
      for_sponsors_tier(sponsors_tiers.pluck(:id))
    end

    scope :for_sponsors_tier, ->(tier_id) { for_sponsors_tiers.where(subscribable_id: tier_id) }

    scope :for_sponsors_tiers, -> { where(subscribable_type: SponsorsTier.name) }

    scope :trial_ending_in_four_days, -> {
      joins(:pending_plan_change)
        .free_trial
        .where(pending_plan_changes: { active_on: GitHub::Billing.today + 4.days })
    }

    scope :non_free_trial, -> { where(free_trial: false) }
    scope :free_trial, -> { where(free_trial: true) }
    scope :cancellation, -> { where(quantity: 0) }

    # Returns a list of pending item changes that are eligible for
    # a free trial expiration reminder.
    #
    # No subscription addons using Billing::ProductUUID are eligible under this codepath,
    # so we want to filter them out.
    # In the future, we may want to have this configured at the product level and
    # filtered based on that, but for now we just filter out ProductUUID.
    scope :free_trial_expiring_internal_reminder_eligible, -> {
      trial_ending_in_four_days
        .not_subscribable_Billing_ProductUUID
    }

    delegate :active_on, to: :pending_plan_change

    # Note: This will force cancellation of in-app purchased subscriptions.
    sig { params(skip_sync: T::Boolean).void }
    def run(skip_sync: false)
      update = Billing::SubscriptionItemUpdater.perform \
        force: true,
        subscribable: subscribable,
        quantity: quantity,
        sender: actor,
        end_free_trial: free_trial,
        plan_subscription: T.must(plan_subscription),
        skip_sync: skip_sync,
        organization: organization

      instrument_run(result: update.result)
    end

    sig { returns(T::Boolean) }
    def undo_trial_cancellation
      return false unless free_trial_cancellation?

      update(quantity: T.must(subscription_item).quantity)
    end

    sig { returns(T::Boolean) }
    def free_trial_cancellation?
      free_trial? && cancellation?
    end

    sig { params(kwargs: T.untyped).returns(Billing::Money) }
    def price(**kwargs)
      Billing::Money.new((
        subscribable_base_price *
        quantity *
        service_percent_remaining
      ))
    end

    sig { returns(Billing::Money) }
    def subscribable_base_price
      subscribable.base_price(duration: subscribable.billing_cycle || plan_duration)
    end

    sig { returns(Float) }
    def service_percent_remaining
      days_billed = T.cast((effective_next_billing_date - active_on), Rational).to_f

      percent = days_billed / billable_entity.subscription.duration_in_days
      percent == 0 ? 1.0 : percent
    end

    sig { returns(Date) }
    def effective_next_billing_date
      next_billing_date = T.must(billable_entity.next_billing_date)
      if next_billing_date.to_date >= active_on
        next_billing_date
      elsif billable_entity.yearly_plan?
        next_billing_date + 1.year
      else
        next_billing_date + 1.month
      end
    end

    sig { returns(String) }
    def abbr_title
      if subscribable_Billing_ProductUUID?
        "Subscription"
      elsif subscribable_SponsorsTier?
        "Sponsorship"
      else
        "Marketplace"
      end
    end

    sig { returns(String) }
    def abbr_prefix
      if subscribable_Billing_ProductUUID?
        "SUB"
      elsif subscribable_SponsorsTier?
        "SP"
      else
        "MP"
      end
    end

    sig { returns(String) }
    def product_codename
      return subscribable.codename if subscribable_Billing_ProductUUID?

      subscribable_type.to_s.underscore
    end

    sig { returns(String) }
    def subscribable_name
      if subscribable_Billing_ProductUUID?
        subscribable.name
      else
        listing_name + " " + subscribable.name
      end
    end

    sig { returns(T::Boolean) }
    def cancellation?
      quantity == 0
    end

    sig { returns(T::Boolean) }
    def can_apply?
      async_can_apply?.sync
    end

    sig { returns(Promise[T::Boolean]) }
    def async_can_apply?
      async_listing.then do |listing|
        if listing
          listing.draft?
        else
          false
        end
      end
    end

    delegate :actor, :user, :customer, to: :pending_plan_change

    delegate :plan_duration, to: :pending_cycle
    delegate :billing_cycle,
             :product_key,
             to: :subscribable, allow_nil: true, prefix: :new

    delegate :pending_cycle, to: :billable_entity

    sig { returns(T.nilable(Billing::PlanSubscription)) }
    def plan_subscription
      # If no plan subscription was explicitly recorded on this record, then the record was made at a time where
      # users/customers only had a single, general-purpose plan subscription, so that's the best guess for which subscription
      # this legacy pending change might be associated with:
      super || billable_entity.plan_subscription
    end

    sig { returns(T::Boolean) }
    def has_active_subscription?
      return false unless subscribable.is_a?(Billing::ProductUUID)
      return false unless plan_subscription = self.plan_subscription
      product_type = subscribable.product_type

      plan_subscription.has_active_subscription_to?(product_type: product_type)
    end

    sig { returns(T.nilable(::Billing::SubscriptionItem)) }
    def active_subscription_item
      return unless subscribable.is_a?(Billing::ProductUUID)
      return unless plan_subscription = self.plan_subscription
      product_type = subscribable.product_type

      plan_subscription.active_subscription_to(product_type: product_type)
    end

    sig { returns(T.nilable(::Billing::SubscriptionItem)) }
    def subscription_item
      return unless plan_subscription = self.plan_subscription

      if subscribable.is_a?(Billing::ProductUUID)
        product_uuids = Billing::ProductUUID.where(
          product_type: subscribable.product_type
        )
        plan_subscription.active_subscription_items.find_by(subscribable: product_uuids)
      elsif subscribable.is_a?(Marketplace::ListingPlan)
        listing = T.cast(self.listing, Marketplace::Listing)
        plan_subscription.subscription_item_for_marketplace_listing(listing, organization: organization)
      elsif subscribable.is_a?(SponsorsTier)
        listing = T.cast(self.listing, SponsorsListing)
        plan_subscription.subscription_item_for_sponsors_listing(listing,
          subscribable: subscribable,
          organization: organization
        )
      else
        raise "Invalid subscribable type"
      end
    end

    sig { returns(String) }
    def platform_type_name
      "PendingMarketplaceChange"
    end

    sig { params(actor: ::User).void }
    def instrument_undo_sponsorship_cancellation(actor:)
      return unless subscribable_SponsorsTier?

      # Hydro
      GlobalInstrumenter.instrument(
        "sponsors.undo_sponsorship_cancellation",
        actor: actor,
        sponsorship: T.must(subscription_item).sponsorship, tier: subscribable
      )
    end

    private

    sig { void }
    def plan_subscription_belongs_to_a_billable_entity
      return if billable_entity.nil?

      user = self.user
      plan_subscription = T.must(self.plan_subscription)

      mismatched_plan_subscription_user = user.present? && plan_subscription.user != user
      mismatched_plan_subscription_customer = customer.present? && plan_subscription.customer != customer

      if mismatched_plan_subscription_user && mismatched_plan_subscription_customer
        errors.add(:plan_subscription,
          "plan subscription has no corresponding user/customer and must belong to #{user} or #{customer}")
        return
      end

      if mismatched_plan_subscription_user
        errors.add(:plan_subscription, "must belong to #{user}")
      end

      if mismatched_plan_subscription_customer
        errors.add(:plan_subscription, "must belong to #{customer}")
      end
    end

    sig { returns(String) }
    def event_prefix
      "pending_subscription_change"
    end

    sig { void }
    def instrument_creation
      payload = instrument_payload
      payload[:actor] = actor if actor

      if subscription_item = self.subscription_item
        payload[:marketplace_listing_plan_was] = subscription_item.subscribable_name
        payload[:quantity_was] = subscription_item.quantity
      end

      GitHub.dogstats.increment("billing.#{event_prefix}.create", tags: ["product:#{product_codename}"])
      instrument :create, payload
    end

    sig { void }
    def instrument_destroy
      payload = instrument_payload
      payload[:actor] = actor if actor
      GitHub.tracer.in_span("instrument_destroy", kind: :internal) do |span|
        span.add_attributes({ "product" => product_codename })
      end

      # Additional logging to help us track down https://github.com/github/octogrowth/issues/2422
      if product_codename == "github.advanced_security.v0.month"
        exec_stack = caller.join("\n")
        GitHub.logger.info("Pending subscription item change destroyed. Stack:\n#{exec_stack}", payload)
      end

      GitHub.dogstats.increment("billing.#{event_prefix}.destroy", tags: ["product:#{product_codename}"])
      instrument :destroy, payload
    end

    sig { params(result: Billing::Public::ResultStruct).void }
    def instrument_run(result:)
      payload = instrument_payload

      payload[:success] = result.success
      if !result.success
        payload[:errors] = result.errors.join(", ")
        GitHub.dogstats.increment("billing.#{event_prefix}.error", tags: ["product:#{product_codename}"])
      end

      GitHub.dogstats.increment("billing.#{event_prefix}.run", tags: ["product:#{product_codename}"])
      instrument :run, payload
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def instrument_payload
      {
        active_on: active_on,
        quantity: quantity.to_i,
        free_trial: !!free_trial,
        subitm_codename: product_codename,
        id: id
      }.tap do |p|
        if billable_entity.is_a?(Customer)
          p[customer.business.event_prefix] = customer.business
        elsif billable_entity.respond_to?(:event_prefix)
          p[billable_entity.event_prefix] = billable_entity
        end
        if listing = self.listing
          p.merge!(
            marketplace_listing_id: listing.id,
            marketplace_listing: listing.try(:name) || listing.try(:slug),
            marketplace_listing_plan: subscribable.name,
          )
        end
      end
    end
  end
end
