# typed: strict
# frozen_string_literal: true

module Billing
  class PlanSubscription < ApplicationRecord::Domain::Users

    include Scientist

    include Instrumentation::Model
    include GitHub::Relay::GlobalIdentification
    include GitHub::ServiceMapping
    include GitHub::Validations
    include ::Billing::PlanSubscription::Synchronization
    include ::Billing::PlanSubscription::SynchronizationStatus

    APPLE_IAP = "Apple In-App Purchase"
    PAYMENT_GATEWAY_FIELD = "PaymentGateway__c"

    belongs_to :customer, required: true
    belongs_to :user, inverse_of: false, required: false

    # Public: Represents the billing purpose of this plan subscription, like what kind of purchases is the Zuora
    # subscription intended to be used for. Might not match the purpose of the Zuora account this plan subscription
    # is tied to (via the Customer record).
    enum :purpose, {
      general:  0, # any and all billing
      sponsors: 1, # sponsorships only
    }, suffix: true

    has_many :subscription_items, dependent: :destroy, class_name: "Billing::SubscriptionItem"
    has_many :past_subscription_items, -> { T.unsafe(self).cancelled }, class_name: "Billing::SubscriptionItem"
    has_many :active_subscription_items, -> { T.unsafe(self).active }, class_name: "Billing::SubscriptionItem"
    has_many :product_uuid_subscription_items, -> { T.unsafe(self).with_product_uuid_type }, class_name: "Billing::SubscriptionItem"
    has_many :active_product_uuid_subscription_items, -> { T.unsafe(self).active.with_product_uuid_type }, class_name: "Billing::SubscriptionItem"
    has_many :past_product_uuid_subscription_items, -> { T.unsafe(self).cancelled.with_product_uuid_type }, class_name: "Billing::SubscriptionItem"
    has_many :active_marketplace_listing_subscription_items, -> { T.unsafe(self).with_any_active_marketplace_listing_plans }, class_name: "Billing::SubscriptionItem"

    has_many :subscription_sync_statuses, dependent: :destroy

    has_many :product_uuids, through: :product_uuid_subscription_items

    validates :user_id, uniqueness: { scope: :purpose, allow_blank: true }

    validates :apple_transaction_id, uniqueness: { allow_nil: true, case_sensitive: false }

    validates :apple_receipt_id, length: { maximum: 65535 }, unicode3: true, allow_blank: true

    validate :purpose_valid_for_customer
    validate :ensure_better_suited_customer_doesnt_exist_for_purpose, on: :create

    scope :for_user, ->(user_or_id) { where(user_id: user_or_id) }
    scope :for_business, ->(business) { where(customer_id: business.customer_id) }
    scope :with_purpose, ->(purpose) { where(purpose: purpose) }

    # plan, plan_duration, seats, and payment_method_token are all stored in
    # the Users table. These four methods can be removed once we've relocated
    # the columns to PlanSubscription.
    delegate :billed_on,
             :coupon,
             :data_packs,
             :payment_method_token,
             :plan,
             :plan_name,
             :plan_duration_in_months,
             :seats,
             :yearly_plan?,
             :metered_billing_overage_allowed?,
      to: :billable_entity, allow_nil: true

    delegate :business, to: :customer, allow_nil: true

    delegate :zuora_account,
      :zuora_account_id,
      :zuora_account_number,
      to: :customer

    delegate :active?, to: :external_subscription, allow_nil: true

    after_commit :synchronize_later, on: :create, unless: :skip_synchronize_later
    after_commit :reset_memoized_attributes, on: :update, if: :saved_change_to_zuora_subscription_number?

    sig { returns(T.nilable(T::Boolean)) }
    attr_accessor :skip_synchronize_later

    before_destroy :queue_external_subscription_cancellation

    # TODO: Search for all instances where this method is called
    # and replace or migrate over to the new subscription rate plan charges
    serialize :zuora_rate_plan_charges, type: Hash

    # TODO: rename this to zuora_rate_plan_charges once we get rid of the serialized field
    has_many :subscription_rate_plan_charges, as: :plan_subscription,
      class_name: "Billing::PlanSubscription::ZuoraRatePlanCharge",
      dependent: :destroy


    sig { returns(T::Hash[String, T::Hash[Symbol, T.untyped]]) }
    def zuora_rate_plan_charges
      if read_from_zuora_rate_plan_charges_table_enabled?
        subscription_rate_plan_charges
          .index_by(&:product_rate_plan_charge_id)
          .transform_values!(&:to_serialized_hash)
      else
        science "zuora_rate_plan_charges_table" do |e|
          e.context(plan_subscription_id: id)

          e.use { super }
          e.try do
            # TODO: we serialize to hash in case there's usages out there that
            # use hash methods instead
            subscription_rate_plan_charges
              .index_by(&:product_rate_plan_charge_id)
              .transform_values!(&:to_serialized_hash)
          end
        end
      end
    end


    sig { returns(T::Boolean) }
    def read_from_zuora_rate_plan_charges_table_enabled?
      if billable_entity = self.billable_entity
        billable_entity.feature_enabled?(:read_from_zuora_rate_plan_charges_table)
      else
        GitHub.flipper[:read_from_zuora_rate_plan_charges_table].enabled?
      end
    end

    sig { returns(T::Boolean) }
    def has_cached_zuora_rate_plan_charges?
      if read_from_zuora_rate_plan_charges_table_enabled?
        subscription_rate_plan_charges.any?
      else
        subscription_rate_plan_charges.any? || zuora_rate_plan_charges.present?
      end
    end

    sig { returns(T::Boolean) }
    def active_charges?
      active_metered_charges? || active_non_metered_charges?
    end

    sig { returns(T::Boolean) }
    def active_metered_charges?
      if sponsors_purpose?
        false
      else
        metered_billing_overage_allowed? || ::Copilot.copilot_object(T.must(billable_entity)).copilot_for_business_enabled?
      end
    end

    sig { returns(T::Boolean) }
    def active_non_metered_charges?
      if sponsors_purpose?
        # For a Sponsors-specific subscription, only the subscription items (which represent sponsorships) are
        # relevant when considering if the subscription has active charges. This is because the billable entity's
        # GitHub plan, data packs, and metered billing overages are only affected by the general-purpose subscription.
        active_subscription_items.exists?
      else
        plan&.paid? || data_packs.to_i.positive? || active_subscription_items.select(&:subscribable_paid?).any?
      end
    end

    sig { returns(T::Boolean) }
    def cancelled_or_non_zuora?
      # ZuoraSynchronizer#cancel calls Billing::PlanSubscription#clear_external_subscription_references which wipes
      # these fields when the subscription is cancelled, so if these fields are wiped that implies a) the subscription
      # was cancelled or b) it was never on Zuora to begin with.
      !!(zuora_subscription_number.blank? &&
        zuora_subscription_id.blank? &&
        !has_cached_zuora_rate_plan_charges?)
    end

    sig { returns(T::Boolean) }
    def cancellable?
      # Sponsors-invoiced plan subscriptions should only be updated
      return false if sponsors_invoiced?
      # Enterprise plan subscriptions should only be updated
      return false unless billable_user?

      !active_charges?
    end

    sig { params(product_key: String, product_type: String, billing_duration: T.nilable(String)).returns(T::Boolean) }
    def has_active_subscription_to?(product_key:, product_type:, billing_duration: nil)
      find_active_subscription_to(product_key: product_key, product_type: product_type, billing_duration: billing_duration).exists?
    end

    sig { params(product_key: String, product_type: String, billing_duration: T.nilable(String)).returns(ActiveRecord::AssociationRelation) }
    def find_active_subscription_to(product_key:, product_type:, billing_duration: nil)
      product_uuid_scope = Billing::ProductUUID.where(product_key: product_key, product_type: product_type)
      if billing_duration
        product_uuid_scope = product_uuid_scope.where(billing_cycle: billing_duration)
      end

      active_subscription_items.where(subscribable: product_uuid_scope)
    end

    sig { params(product_key: String, product_type: String, billing_duration: T.nilable(String)).returns(::Billing::SubscriptionItem) }
    def active_subscription_to(product_key:, product_type:, billing_duration: nil)
      find_active_subscription_to(product_key: product_key, product_type: product_type, billing_duration: billing_duration).take
    end

    sig { returns(Promise[::Billing::Types::Account]) }
    def async_billable_entity
      async_user.then do |user|
        if user
          user
        else
          async_customer.then { |customer| T.must(customer).async_business }
        end
      end
    end

    # Returns either the user or the business
    sig { returns(T.nilable(::Billing::Types::Account)) }
    def billable_entity
      billable_user? ? user : business
    end

    sig { returns(T::Boolean) }
    def billable_user?
      user_id.present?
    end

    sig { returns(T::Boolean) }
    def billable_business?
      !billable_user? && business.present?
    end

    # Returns whether the user's plan matches the given plan.
    # It does NOT guarantee that the user's plan has been synchronized to the remote subscription service
    sig { params(plan: T.nilable(T.any(String, Symbol, GitHub::Plan))).returns(T::Boolean) }
    def subscribed_to_github_plan?(plan:)
      return false unless billable_entity

      plan_name.to_s == plan.to_s
    end

    sig { params(product_rate_plan_charge_id: String).returns(T.nilable(String)) }
    def zuora_rate_plan_charge_number(product_rate_plan_charge_id:)
      if read_from_zuora_rate_plan_charges_table_enabled?
        subscription_rate_plan_charges.detect do |charge|
          charge.product_rate_plan_charge_id == product_rate_plan_charge_id
        end&.number
      else
        science "zuora_rate_plan_charges_table" do |e|
          e.context(
            plan_subscription_id: id,
            product_rate_plan_charge_id: product_rate_plan_charge_id
          )

          e.use { zuora_rate_plan_charges.dig(product_rate_plan_charge_id, :number) }
          e.try do
            subscription_rate_plan_charges.detect do |charge|
              charge.product_rate_plan_charge_id == product_rate_plan_charge_id
            end&.number
          end
        end

      end
    end

    sig { returns(T.nilable(::Billing::Zuora::Subscription)) }
    def zuora_subscription
      if defined?(@_zuora_subscription)
        GitHub.dogstats.increment("zuora.subscription.cache_hit")
        return @_zuora_subscription
      end

      GitHub.dogstats.increment("zuora.subscription.cache_miss")
      @_zuora_subscription = T.let(Billing::Zuora::Subscription.find(zuora_subscription_number), T.nilable(::Billing::Zuora::Subscription))
    end

    sig { returns(::Billing::Zuora::Subscription) }
    def zuora_subscription!
      if defined?(@_zuora_subscription) && !@_zuora_subscription.nil?
        GitHub.dogstats.increment("zuora.subscription.cache_hit")
        return @_zuora_subscription
      end

      GitHub.dogstats.increment("zuora.subscription.cache_miss")
      @_zuora_subscription = T.let(Billing::Zuora::Subscription.find!(zuora_subscription_number), T.nilable(::Billing::Zuora::Subscription))
      T.must(@_zuora_subscription)
    end

    # Resumes the Zuora subscription and updates the subscription ID if successful
    sig { returns(T::Boolean) }
    def resume
      return false unless zuora_subscription
      return true unless T.must(zuora_subscription).suspended?

      response = T.must(zuora_subscription).resume
      if response["success"]
        update_from_zuora_subscription
      end

      instrument(:resume, { external_result: response })
      response["success"]
    end

    # Suspends the Zuora subscription and updates the subscription ID if successful
    sig { returns(T::Boolean) }
    def suspend
      return false unless zuora_subscription
      return true if T.must(zuora_subscription).suspended?

      response = T.must(zuora_subscription).suspend
      if response["success"]
        update_from_zuora_subscription
      end

      instrument(:suspend, { external_result: response })
      response["success"]
    end

    # Updates the plan subscription information from the Zuora subscription
    sig { params(zuora_subscription_object: T.nilable(::Billing::Zuora::Subscription)).returns(T::Boolean) }
    def update_from_zuora_subscription(zuora_subscription_object: nil)
      reset_memoized_attributes unless zuora_subscription_object.present?

      zuora_subscription_object ||= zuora_subscription!

      rate_plan_charges = {}
      zuora_subscription_object.active_rate_plan_charges.each do |rate_plan_charge|
        rate_plan_charges[rate_plan_charge.product_rate_plan_charge_id] = {
          number: rate_plan_charge.number,
          charged_through_date: rate_plan_charge.charged_through_date
        }
      end

      success = update(
        zuora_subscription_number: zuora_subscription_object.number,
        zuora_subscription_id: zuora_subscription_object.id,
        zuora_rate_plan_charges: rate_plan_charges,
      )
      if new_rate_plan_charges_enabled?
        result = Billing::PlanSubscription::ZuoraRatePlanCharge.reconcile(
          plan_subscription: self,
          active_charges_from_zuora: zuora_subscription_object.active_rate_plan_charges,
          success: success
        )
        if result
          subscription_rate_plan_charges.reload
        end

        GitHub.dogstats.increment("billing.plan_subscription.charge_updates", tags: ["success:#{!!result}", "sales_serve:false"])
      end

      success
    end

    sig { returns(T::Boolean) }
    def new_rate_plan_charges_enabled?
      flag = :new_zuora_rate_plan_charges
      !!(billable_entity&.feature_enabled?(flag) || GitHub.flipper[flag].enabled?)
    end

    sig { returns(T::Boolean) }
    def clear_external_subscription_references
      success = update(
        zuora_subscription_number: nil,
        zuora_subscription_id: nil,
        zuora_rate_plan_charges: {},
      )

      if success && new_rate_plan_charges_enabled?
        result = Billing::PlanSubscription::ZuoraRatePlanCharge.reconcile(
          plan_subscription: self,
          active_charges_from_zuora: [],
          success: success
        )
        GitHub.dogstats.increment(
          "billing.plan_subscription.charge_clears", tags: ["success:#{!!result}", "sales_serve:false"]
        )
        if result
          subscription_rate_plan_charges.reload
        end
      end

      success
    end

    sig { void }
    def attach_orphaned_zuora_subscription
      return if zuora_subscription_number.present?

      attached_zuora_subscriptions = user&.plan_subscriptions&.pluck(:zuora_subscription_number).to_a.compact
      zuora_subscriptions = zuora_object_account&.subscriptions.to_a
      available_zuora_subscriptions = zuora_subscriptions.select do |sub|
        sub["status"] == "Active" && !attached_zuora_subscriptions.include?(sub["subscriptionNumber"])
      end

      # Zuora subscriptions can be configured to use either the sponsors-specific payment gateway or the
      # general payment gateway. Plan subscriptions must be attached to the correct type of Zuora subscription
      # based on their purpose.
      active_subscription = if sponsors_purpose?
        available_zuora_subscriptions.detect do |zuora_subscription|
          zuora_subscription[PAYMENT_GATEWAY_FIELD] == Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2
        end
      else
        available_zuora_subscriptions.detect do |zuora_subscription|
          zuora_subscription[PAYMENT_GATEWAY_FIELD] != Billing::Zuora::PaymentGateway::SPONSORS_STRIPE_V2
        end
      end

      if active_subscription
        GitHub.dogstats.increment("billing.orphaned_zuora_subscription.count")
        update \
          zuora_subscription_id: active_subscription["id"],
          zuora_subscription_number: active_subscription["subscriptionNumber"]
      else
        GitHub.dogstats.increment("billing.orphaned_zuora_subscription.not_found")
      end
    end

    # Public: Default event prefix for GitHub instrumentation. We're overriding
    #         it here because we don't want to use the default of
    #         "billing/plan_subscription".
    sig { returns(Symbol) }
    def event_prefix
      :plan_subscription
    end

    # Public: Default event payload for GitHub instrumentation
    sig { returns(T::Hash[Symbol, T.untyped]) }
    def event_payload
      payload = { plan_subscription_id: id }

      if billable_business?
        payload[:business] = business
      elsif user.is_a?(Organization)
        payload[:org] = user
      elsif user&.billable?
        payload[:user] = user
      end

      payload[:purpose] = purpose

      payload
    end

    # Public: Retry a charge for a Past Due subscription
    sig { returns(::GitHub::Billing::Result) }
    def retry_charge
      billable_entity = T.must(self.billable_entity)
      log_payload = {
        "code.namespace" => self.class.name,
        "code.function" => "retry_charge",
        "gh.billing.billable_entity.id" => billable_entity.id,
        "gh.billing.billable_entity.type" => billable_entity.class.name,
        "gh.billing.billable_entity.dunning" => billable_entity.dunning?
      }
      GitHub.logger.with_named_tags(log_payload) do
        GitHub.logger.info("Retry charge")

        if !billable_entity.dunning?
          GitHub::Billing::Result.success
        elsif zuora_subscription_number?
          response = if retry_charge_using_apm?
            GitHub.zuorest_client.create_apm_payment_run(
              {
                target_date: GitHub::Billing.today.to_s,
                custom: "Account.Id = '#{T.must(customer).zuora_account_id}'"
              }
            )
          else
            GitHub.zuorest_client.create_invoice_collect accountKey: zuora_account_id
          end

          if response[:success]
            GitHub.logger.info("gh.billing.zuora.success" => response[:success])
          else
            GitHub.logger.info("gh.billing.zuora.response" => response)
          end

          ::GitHub::Billing::Result.from_zuora(response)
        end
      end
    end

    # Public: Returns the balance on the subscription in dollars. Negative
    # balance means we owe the customer.
    sig { returns(BigDecimal) }
    def balance
      balance_in_cents / BigDecimal(100)
    end

    # Public: Returns whether or not there is a positive balance on
    # the plan subscription
    sig { returns(T::Boolean) }
    def has_balance?
      balance_in_cents > 0
    end

    # Public: Generates Zuora related payloads to send to Zuora during sync.
    sig { returns(Billing::PlanSubscription::ZuoraSubscriptionParams) }
    def zuora_params
      Billing::PlanSubscription::ZuoraSubscriptionParams.new(plan_subscription: self)
    end

    # Public: Cancel the Zuora subscription
    sig { params(force: T::Boolean).returns(T::Boolean) }
    def cancel_external_subscription(force: false)
      return false unless zuora_subscription_number.present?
      if !force && active_non_metered_charges?
        subscription_billable_entity = T.must(billable_entity)
        GitHub.logger.info(
          "Skipped cancellation of external subscription due to active non-metered charges being present",
          {
            "code.function": __method__,
            "gh.billing.billable_entity.id": subscription_billable_entity.id,
            "gh.billing.billable_entity.login": subscription_billable_entity.display_login,
            "gh.billing.billable_entity.type": subscription_billable_entity.class.name,
            "gh.billing.customer.id": subscription_billable_entity.customer&.id,
            "gh.billing.customer.requires_manual_transactions": subscription_billable_entity.customer&.requires_manual_transactions?,
            "gh.billing.customer.zuora_account_id": subscription_billable_entity.customer&.zuora_account_id,
            "gh.billing.customer.zuora_subscription_number": zuora_subscription_number,
            "gh.billing.plan_subscription.id": self.id,
          }
        )
        return false
      end
      !!CloseOutZuoraSubscriptionJob.perform_later(
        zuora_subscription_number: zuora_subscription_number,
        plan_subscription: self,
      )
    end

    # Public: Immediately cancel all paid subscription items associated with this plan subscription
    sig { params(skip_sync: T::Boolean).returns(T::Array[Billing::Public::SubscriptionItems::ResultStruct]) }
    def cancel_subscription_items!(skip_sync: false)
      results = subscription_items.active.select(&:subscribable_paid?).map do |item|
        item.cancel!(force: true, skip_sync: true)
      end
      synchronize_later unless skip_sync
      results
    end

    # Public: Returns this plan subscription's active subscription item for a Marketplace listing.
    #
    # marketplace_listing_or_id - a Marketplace::Listing or its ID
    # organization - a self-serve enterprise owned organization, if applicable.
    #
    # Returns nil or a Billing::SubscriptionItem.
    sig { params(marketplace_listing_or_id: T.any(Marketplace::Listing, Integer), organization: T.nilable(Organization)).returns(T.nilable(Billing::SubscriptionItem)) }
    def subscription_item_for_marketplace_listing(marketplace_listing_or_id, organization: nil)
      listing_plans_ids = Marketplace::ListingPlan.where(marketplace_listing_id: marketplace_listing_or_id).pluck(:id)
      active_subscription_items.for_marketplace_listing_plans(listing_plans_ids).where(organization_id: organization&.id).last
    end

    # Public: Get the subscription item for this plan subscription for a particular Sponsors maintainer. Will
    # prefer the active subscription item for any monthly sponsorship this plan subscription has for the maintainer,
    # if both it and an active one-time payment's subscription item exist.
    #
    # sponsors_listing_or_id - the SponsorsListing or its ID that represents the maintainer whose sponsorship's
    #                          subscription item we want to get
    # subscribable - optional SponsorsTier that, if supplied, will be used to find an inactive sub item for the tier
    #                when no active subscription items exist. This supports delayed sponsorship payment via delayed
    #                sub item activation.
    # organization - optional Organization used to disambiguate enterprise account member org sponsorships
    #
    # Returns a Billing::SubscriptionItem or nil.
    sig do
      params(
        sponsors_listing_or_id: T.any(SponsorsListing, Integer),
        subscribable: T.nilable(SponsorsTier),
        organization: T.nilable(Organization)
      ).returns(T.nilable(Billing::SubscriptionItem))
    end
    def subscription_item_for_sponsors_listing(sponsors_listing_or_id, subscribable: nil, organization: nil)
      active_items_for_listing = active_subscription_items.for_sponsors_listing(sponsors_listing_or_id)

      # enterprise-account sub items require an org to disambiguates sponsorships from different member orgs
      requires_org = organization.present? && organization != billable_entity

      active_items = if requires_org
        active_items_for_listing.where(organization: organization)
      else
        active_items_for_listing
      end

      if active_items.empty?
        if subscribable.present?
          sub_items = if requires_org
            subscription_items.where(subscribable: subscribable, organization: organization)
          else
            subscription_items.where(subscribable: subscribable)
          end
          return sub_items.first
        else
          return
        end
      end

      return active_items.first if active_items.one?

      # `subscribable` is used by #recurring_sponsorship?
      GitHub::PrefillAssociations.prefill_associations(active_items, :subscribable)

      active_items.detect(&:recurring_sponsorship?)
    end

    # Public: The external subscription
    sig { returns(T.nilable(::Billing::Zuora::Subscription)) }
    def external_subscription
      zuora_subscription if zuora_subscription_number?
    end

    sig { returns(T::Boolean) }
    def has_external_subscription?
      zuora_subscription_number?
    end

    sig { returns(T.nilable(String)) }
    def external_subscription_type
      if zuora_subscription_number?
        EXTERNAL_SUBSCRIPTION_TYPES[:zuora]
      end
    end

    sig { returns(T.nilable(String)) }
    def sync_platform_type
      external_subscription_type ||
        (EXTERNAL_SUBSCRIPTION_TYPES[:zuora] if zuora_user?)
    end

    sig { returns(Billing::Money) }
    def discount
      Billing::Pricing.new(account: user, plan: plan).discount
    end

    sig { returns(::Billing::Types::Numeric) }
    def coupon_amount
      return 0 unless coupon

      if coupon.percentage?
        coupon.discount * 100
      else
        coupon.discount * plan_duration_in_months
      end
    end

    sig { returns(Integer) }
    def additional_seats
      return 0 if plan.per_repository?

      [seats - plan.base_units, 0].max
    end

    sig { returns(Billing::Money) }
    def unit_price
      if yearly_plan?
        Billing::Money.new(plan.yearly_unit_cost_in_cents)
      else
        Billing::Money.new(plan.unit_cost_in_cents)
      end
    end

    sig { returns(Billing::Money) }
    def base_price
      if yearly_plan?
        Billing::Money.new(plan.yearly_cost_in_cents)
      else
        Billing::Money.new(plan.cost_in_cents)
      end
    end

    sig { returns(Billing::Money) }
    def data_packs_unit_price
      Billing::Money.new(Asset::Status.data_pack_unit_price * (yearly_plan? ? 12 : 1))
    end

    sig { returns(String) }
    def platform_type_name
      "Subscription"
    end

    sig { returns(T::Boolean) }
    def on_free_trial?
      if billable_business?
        return false if business.trial_conversion_initiated? || (business.trial? && business.autopay_disabled_by_india_rbi?)
        return business.trial?
      end
      user = self.user

      return false unless user

      user.plan_trial_active?(plan.name).tap do
        # We reload the user to ensure we have the most up-to-date plan information after we check for a trial.
        # This is because there's a race condition when customers are upgrading to paid customers while in a
        # free trial which results in them being billed for the enterprise with 50 users (which is what they
        # get during the trial), rather than being billed for whatever plan/seat usage they are trying to
        # purchase. This is caused by us having a stale copy of the `user` which doens't have the new plan and
        # seat information yet and a fresh answer to whether they're on a trial or not. This does not fix
        # the race condition, but by reloading the user we'll be ensuring we are billing the most up to date
        # plan and seat count.
        user.reload
      end
    end

    sig { returns(T::Boolean) }
    def apple_iap_subscription?
      apple_receipt_id.present? && apple_transaction_id.present?
    end

    sig { returns(Promise[String]) }
    def async_plan_duration
      async_user.then do |user|
        if billable_user?
          T.must(user).async_plan_duration
        else
          async_billable_entity.then do |business|
            business.plan_duration
          end
        end
      end
    end

    sig { returns(T::Boolean) }
    def has_free_usage_product?
      false
    end

    sig { returns(T::Boolean) }
    def has_valid_payment_method?
      user_or_biz = billable_entity
      return false unless user_or_biz
      if sponsors_purpose?
        user_or_biz.has_valid_payment_method_for_sponsorships?(feature_type: :noncommercial)
      else
        user_or_biz.has_valid_payment_method?(feature_type: :noncommercial)
      end
    end

    sig { returns(BigDecimal) }
    def payment_amount
      if sponsors_purpose?
        Billing::Pricing.new(
          plan_subscription: self,
        ).recurring_sponsorable_item_cost.dollars
      else
        T.must(billable_entity).payment_amount
      end
    end

    # Public: String describing the duration (e.g. "year", "month")
    #
    # Sponsors-purpose plan subscription may have a different duration than
    # the user's general-purpose plan subscription. For example, sponsorships
    # may be billed monthly even though the user's GitHub plan is billed yearly.
    sig { returns(String) }
    def plan_duration
      if sponsors_purpose?
        T.must(billable_entity).sponsors_plan_duration
      else
        T.must(billable_entity).plan_duration
      end
    end

    sig { params(listing: T.nilable(Marketplace::Listing)).returns(T::Boolean) }
    def eligible_for_free_trial_on_listing?(listing)
      return false unless listing

      listing_plans_ids = Marketplace::ListingPlan.where(marketplace_listing_id: listing.id).pluck(:id)
      items = subscription_items.for_marketplace_listing_plans(listing_plans_ids)
      items.none? { |item| item.async_subscribable.then { item.disqualifies_for_free_trial? } }
    end

    sig { params(kwargs: T.untyped).returns(::Billing::Types::Numeric) }
    def post_trial_prorated_total_price(**kwargs)
      async_post_trial_prorated_total_price(listing_plan: kwargs[:listing_plan], user: kwargs[:user], quantity: kwargs[:quantity]).sync
    end

    sig { params(listing_plan: Marketplace::ListingPlan, user: User, quantity: T.nilable(Integer)).returns(Promise[::Billing::Types::Numeric]) }
    def async_post_trial_prorated_total_price(listing_plan:, user:, quantity: nil)
      item = SubscriptionItem.new(
        subscribable_type: listing_plan.class.name,
        subscribable_id: listing_plan.id,
        quantity: quantity,
      )

      time_until_trial_ends = Subscription::FREE_TRIAL_LENGTH + 1.day
      subscription = Subscription.new(
        duration_in_months: user.subscription.duration_in_months,
        ends: user.subscription.next_bill_date_after(date: user.subscription.free_trial_end_date),
        active_on: GitHub::Billing.today + time_until_trial_ends,
      )

      item.async_subscribable.then do
        new_prorated_price = Pricing.new(
          plan_duration: user.plan_duration,
          subscription_item: item,
          service_remaining: subscription.service_remaining,
          use_trial_prices: false,
        ).discounted

        if current_subscription_item = user.subscription_item_for_marketplace_listing(listing_plan.marketplace_listing_id)
          current_subscription_item.async_subscribable.then do |subscribable|
            old_prorated_price = subscribable.prorated_total_price(account: user, quantity: current_subscription_item.quantity)
            new_prorated_price - old_prorated_price
          end
        else
          new_prorated_price
        end
      end
    end

    sig do
      params(
        billable_entity: ::Billing::Types::Account,
        plan: T.nilable(String),
        seats: T.nilable(Integer),
        asset_packs: T.nilable(Integer),
        billing_duration: T.nilable(String),
        subscribable: T.nilable(T.any(SponsorsTier, Billing::ProductUUID, Marketplace::ListingPlan)),
        subscribable_quantity: T.nilable(Integer),
      ).returns(::Billing::PlanChange)
    end
    def plan_change(billable_entity:, plan: nil, seats: nil, asset_packs: nil, billing_duration: nil, subscribable: nil, subscribable_quantity: nil)
      async_plan_change(
        billable_entity: billable_entity,
        plan: plan,
        seats: seats,
        asset_packs: asset_packs,
        billing_duration: billing_duration,
        subscribable: subscribable,
        subscribable_quantity: subscribable_quantity,
      ).sync
    end

    sig do
      params(
        billable_entity: ::Billing::Types::Account,
        plan: T.nilable(String),
        seats: T.nilable(Integer),
        asset_packs: T.nilable(Integer),
        billing_duration: T.nilable(String),
        subscribable: T.nilable(T.any(SponsorsTier, Billing::ProductUUID, Marketplace::ListingPlan)),
        subscribable_quantity: T.nilable(Integer),
      ).returns(Promise[::Billing::PlanChange])
    end
    def async_plan_change(billable_entity:, plan: nil, seats: nil, asset_packs: nil, billing_duration: nil, subscribable: nil, subscribable_quantity: nil)
      if billing_duration
        billing_duration = billing_duration == User::BillingDependency::MONTHLY_PLAN ? 1 : 12
      end

      async_subscription_items_for_new_subscription(
        subscribable: subscribable,
        subscribable_quantity: subscribable_quantity,
      ).then do |new_subscription_sub_items|
        new_subscription = Subscription.for_account(billable_entity,
          plan: GitHub::Plan.find(plan),
          seats: seats,
          asset_packs: asset_packs,
          duration_in_months: billing_duration,
          subscription_items: new_subscription_sub_items,
        )
        PlanChange.new(
          billable_entity.subscription,
          new_subscription,
          starting_new_subscription: !billable_entity.external_subscription?
        )
      end
    end

    # Public: Get a list of subscription items that should be part of the new subscription for this plan
    # subscription's user, as part of a plan change, if any.
    sig do
      params(
        subscribable: T.nilable(T.any(SponsorsTier, Billing::ProductUUID, Marketplace::ListingPlan)),
        subscribable_quantity: T.nilable(Integer),
      ).returns(Promise[T.nilable(T::Array[Billing::SubscriptionItem])])
    end
    def async_subscription_items_for_new_subscription(subscribable: nil, subscribable_quantity: nil)
      return Promise.resolve(T.let(nil, T.nilable(T::Array[Billing::SubscriptionItem]))) unless subscribable

      async_new_subscription_item_for(subscribable, subscribable_quantity: subscribable_quantity).then do |new_item|
        async_subscription_items.then do |sub_items|
          sub_items_promises = sub_items.map do |existing_item|
            existing_item.async_subscribable_for_same_listing?(T.unsafe(subscribable)).then do |is_same_listing|
              is_same_listing ? new_item : existing_item
            end
          end

          Promise.all(sub_items_promises).then do |items|
            (items + [new_item]).uniq
          end
        end
      end
    end

    # Public: Build a subscription item for use with a purchase of the given subscribable.
    sig do
      params(
        subscribable: T.any(SponsorsTier, Billing::ProductUUID, Marketplace::ListingPlan),
        subscribable_quantity: T.nilable(Integer)
      ).returns(Promise[Billing::SubscriptionItem])
    end
    def async_new_subscription_item_for(subscribable, subscribable_quantity: nil)
      async_subscription_item_for(subscribable).then do |existing_item|
        SubscriptionItem.new(
          plan_subscription: self,
          quantity: subscribable_quantity.to_i,
          subscribable: subscribable,
          free_trial_ends_on: existing_item&.free_trial_ends_on,
        )
      end
    end

    # Public: Find an existing subscription item on this plan subscription that is for the specified subscribable.
    sig do
      params(
        subscribable: T.nilable(T.any(SponsorsTier, Billing::ProductUUID, Marketplace::ListingPlan))
      ).returns(Promise[T.nilable(Billing::SubscriptionItem)])
    end
    def async_subscription_item_for(subscribable)
      # Subscription items have to have a subscribable, so if we weren't given a subscribable we can bail early:
      return Promise.resolve(T.let(nil, T.nilable(::Billing::SubscriptionItem))) unless subscribable

      async_subscription_items.then do |sub_items|
        sub_items.detect do |item|
          item.subscribable_type == subscribable.class.name && item.subscribable_id == subscribable.id
        end
      end
    end

    sig { returns T.nilable(T::Boolean) }
    def sponsors_invoiced?
      sponsors_purpose? && customer&.sponsors_purpose? && user&.sponsors_invoiced?
    end

    sig { returns(T::Boolean) }
    def unsynced_with_zuora?
      zuora_subscription_id.nil? || zuora_subscription_number.nil?
    end

    # Public: is this plan subscription related to a general-purpose customer?
    sig { returns(T::Boolean) }
    def general_purpose_customer?
      customer = self.customer
      return false unless customer

      customer.general_purpose?
    end

    sig { returns(String) }
    def purpose_description
      return "Sponsors-specific" if sponsors_purpose?
      return "general-purpose" if general_purpose?
      "unknown"
    end

    # Public: Mapping of Billing::SubscriptionItem ids to their respective Organization ids
    #
    # The existence of an organization on a subscription item helps disambiguate ownership in casese like
    # self-serve enterprise accounts. An enterprise account may pay for a subscription item but in the
    # case of e.g. sponsorships that subscription item is also related to the organization as the sponsor.
    #
    # Returns a Hash { Integer Billing::SubscriptionItem id => Integer Organization id }
    sig { returns(T::Hash[Integer, Integer]) }
    def org_id_by_sub_item_id
      subscription_items.where.not(organization_id: nil)
        .pluck(:id, :organization_id)
        .to_h
    end

    # Public: The outstanding balance (if any) from the previous Zuora subscription before it was cancelled.
    # Balance is only cached for 30 days after cancellation for tracking purposes.
    #
    sig { returns(BigDecimal) }
    def cached_outstanding_balance_from_last_cancelled_zuora_subscription
      Billing::Kv.store.get(outstanding_balance_key).value!.to_i / BigDecimal(100)
    end

    # Public: Caches the current balance_in_cents (if non-zero) as the outstanding balance in Billing::Kv.store
    sig { void }
    def cache_outstanding_balance
      return unless has_balance?
      Billing::Kv.store.set(outstanding_balance_key, balance_in_cents.to_s, expires: 30.days.from_now)
      GitHub.dogstats.count("billing.plan_subscription.outstanding_balance", balance,
        tags: ["purpose:#{purpose}", "billable_entity_type:#{billable_entity.class.name}", "disabled:#{billable_entity&.disabled?}"])
    end

    private

    delegate :zuora_object_account, to: :customer

    sig { void }
    def ensure_better_suited_customer_doesnt_exist_for_purpose
      user = self.user
      if sponsors_purpose? && user && general_purpose_customer?
        if !cancelled_or_non_zuora? && user.sponsors_customer.present?
          errors.add(:base, "An active Sponsors-specific plan subscription must be tied to the account's " \
            "Sponsors-specific customer when one exists.")
        end
      end
    end

    sig { void }
    def purpose_valid_for_customer
      customer = self.customer
      return unless customer

      return if sponsors_purpose? && general_purpose_customer?

      unless purpose == customer.purpose
        errors.add(:purpose, "must be #{customer.purpose} to match customer")
      end
    end

    # Should we leverage Zuora Advanced Payment Manager (APM) to retry charges?
    #
    # APM supports per-subscription payment gateways and ensures Sponsors funds don't co-mingle.
    sig { returns(T::Boolean) }
    def retry_charge_using_apm?
      return false unless customer = self.customer
      # TODO we're currently concerned that APM payment runs might not be able to support
      # the ~1k calls/day this generates, so we will start out by only using an APM payment
      # run if they have an active Sponsors-purpose plan subscription.
      #
      # See https://github.com/github/sponsors/issues/4831#issuecomment-1531927165
      sponsors_plan_sub = customer.sponsors_plan_subscription
      !!(sponsors_plan_sub.present? && !sponsors_plan_sub.cancelled_or_non_zuora?)
    end

    sig { void }
    def queue_external_subscription_cancellation
      return unless zuora_subscription_number = self.zuora_subscription_number

      CloseOutZuoraSubscriptionJob.perform_later(zuora_subscription_number: zuora_subscription_number)
    end

    # Internal: is the plan subscription found on zuora
    sig { returns(T::Boolean) }
    def zuora_subscription?
      external_subscription_type == EXTERNAL_SUBSCRIPTION_TYPES[:zuora]
    end

    sig { returns(T::Boolean) }
    def zuora_user?
      !!customer&.zuora?
    end

    EXTERNAL_SUBSCRIPTION_TYPES = T.let({
      zuora: "zuora",
    }.freeze, T::Hash[Symbol, String])

    sig { void }
    def reset_memoized_attributes
      remove_instance_variable(:@_zuora_subscription) if defined?(@_zuora_subscription)
      remove_instance_variable(:@fetched_external_subscription) if defined?(@fetched_external_subscription)
    end

    # The Billing::Kv.store key used to store the outstanding balance from the last cancelled Zuora subscription
    sig { returns(String) }
    def outstanding_balance_key
      "billing_outstanding_balance_#{self.id}"
    end
  end
end
