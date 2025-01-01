# typed: strict
# frozen_string_literal: true

module Billing
  class SubscriptionItemUpdater

    include GitHub::Memoizer

    # Options - with the following keys:
    #   :plan_subscription    - The Billing::PlanSubscription whose subscription item should be updated
    #   :force                - Boolean indicating whether to make the update right now versus scheduling
    #                           it for later; defaults to scheduling it.
    #   :subscribable         - The new subscribable the account would like to switch to, e.g., a SponsorsTier or
    #                           Marketplace::ListingPlan.
    #   :quantity             - How many of the subscribable the account would like to purchase.
    #   :sender               - The authenticated User who is making the change.
    #   :start_free_trial     - Boolean indicating whether a new free-trial period should begin.
    #   :end_free_trial       - Boolean indicating whether the existing free-trial period should stop.
    #   :free_trial_ends_on   - Date on which the free trial should end.
    #   :skip_sync            - Boolean indicating whether the plan subscription should be synchronized
    #                           after the update; defaults to false, meaning the plan subscription
    #                           will be synchronized.
    #   :allow_cancelling_iap - Apple is the source-of-truth for in-app purchases, so we do not
    #                           want to cancel them by default. You can override this by passing in
    #                           true and acknowledging this but it is not recommended given the user
    #                           must now be directed to cancel their subscription in-app.
    #
    # Returns a Billing::Public::SubscriptionItems::ResultStruct or raises Platform::Errors::Unprocessable.
    sig do
      params(
        quantity: Integer,
        sender: T.nilable(User),
        plan_subscription: Billing::PlanSubscription,
        subscribable: T.any(Marketplace::ListingPlan, SponsorsTier, Billing::ProductUUID),
        organization: T.nilable(Organization),
        force: T::Boolean,
        start_free_trial: T::Boolean,
        end_free_trial: T::Boolean,
        free_trial_ends_on: T.nilable(Date),
        skip_sync: T::Boolean,
        allow_cancelling_iap: T::Boolean,
        include_inactive: T::Boolean,
        in_app_purchase: T.nilable(Billing::Public::InAppPurchase),
      ).returns(Billing::Public::SubscriptionItems::ResultStruct)
    end
    def self.perform(
      quantity:,
      sender:,
      plan_subscription:,
      subscribable:,
      organization: nil,
      force: false,
      start_free_trial: false,
      end_free_trial: false,
      free_trial_ends_on: nil,
      skip_sync: false,
      allow_cancelling_iap: false,
      include_inactive: false,
      in_app_purchase: nil
    )
      new(
        quantity:,
        sender:,
        plan_subscription:,
        subscribable:,
        organization:,
        force:,
        start_free_trial:,
        end_free_trial:,
        free_trial_ends_on:,
        skip_sync:,
        allow_cancelling_iap:,
        include_inactive:,
        in_app_purchase:
      ).perform
    end

    sig do
      params(
        quantity: Integer,
        sender: T.nilable(User),
        plan_subscription: Billing::PlanSubscription,
        subscribable: T.any(Marketplace::ListingPlan, SponsorsTier, Billing::ProductUUID),
        organization: T.nilable(Organization),
        force: T::Boolean,
        start_free_trial: T::Boolean,
        end_free_trial: T::Boolean,
        free_trial_ends_on: T.nilable(Date),
        skip_sync: T::Boolean,
        allow_cancelling_iap: T::Boolean,
        include_inactive: T::Boolean,
        in_app_purchase: T.nilable(Billing::Public::InAppPurchase)
      ).void
    end
    def initialize(
      quantity:,
      sender:,
      plan_subscription:,
      subscribable:,
      organization: nil,
      force: false,
      start_free_trial: false,
      end_free_trial: false,
      free_trial_ends_on: nil,
      skip_sync: false,
      allow_cancelling_iap: false,
      include_inactive: false,
      in_app_purchase: nil
    )
      @quantity = T.let(quantity.to_i, Integer)
      @sender = sender
      @plan_subscription = plan_subscription
      @subscribable = subscribable
      @force = force
      @start_free_trial = start_free_trial
      @end_free_trial = T.let(end_free_trial && !quantity.zero?, T::Boolean)
      @free_trial_ends_on = free_trial_ends_on
      @invalidate_free_trials = T.let(false, T::Boolean)
      @skip_sync = skip_sync
      @account = T.let(plan_subscription.user || plan_subscription.customer&.business, T.nilable(Billing::Types::Account))
      @sponsorship_errors = T.let([], T::Array[String])
      @pending_change_scheduled = T.let(false, T::Boolean)
      @organization = organization
      @include_inactive = include_inactive
      @subscription_item = T.let(find_subscription_item, T.nilable(Billing::SubscriptionItem))
      @allow_cancelling_iap = allow_cancelling_iap
      @in_app_purchase = in_app_purchase

      if @subscription_item
        @previous_subscribable = T.let(@subscription_item.subscribable, T.any(SponsorsTier, Marketplace::ListingPlan, Billing::ProductUUID))
        @previously_on_free_trial = T.let(@subscription_item.on_free_trial?, T::Boolean)
        @previous_free_trial_ends_on = T.let(@subscription_item.free_trial_ends_on, T.nilable(Date))
        @previous_quantity = T.let(@subscription_item.quantity, Integer)
        @account = T.let(@subscription_item.account, T.nilable(Billing::Types::Account))
        @organization = organization.nil? ? @subscription_item.organization : organization
      end
    end

    sig { returns(T.nilable(Date)) }
    def update_execution_date
      if schedule_change?
        change_effective_date
      elsif subscription_item.on_free_trial?
        # #on_free_trial? ensures non-nil free_trial_ends_on
        subscription_item.free_trial_ends_on + 1.day
      else
        GitHub::Billing.today
      end
    end

    # Updates an existing subscription item quantity, or creates a new subscription item with a new subscribable
    # while cancelling the old item
    #
    # Returns Hash - { success: true/false, subscription_item: if_success, errors: if_failure }
    sig { returns(Billing::Public::SubscriptionItems::ResultStruct) }
    def perform
      unless @subscription_item.present?
        return Billing::Public::SubscriptionItems::ResultStruct.new(
          result: Billing::Public::ResultStruct.new(success: false, errors: ["Account has no subscription item to update"])
        )
      end
      return Billing::Public::SubscriptionItems::ResultStruct.new(
        result: Billing::Public::ResultStruct.new(success: true),
        subscription_item: subscription_item
      ) if nothing_changed_for_sponsorable_item?

      # The consumer must explicitly override the default behavior to cancel IAP subscriptions. By default, we do not
      # want to cancel IAP subscriptions because Apple is the source-of-truth for in-app purchases.
      if subscription_item.in_app_purchase? && cancelling? && !allow_cancelling_iap
        return Billing::Public::SubscriptionItems::ResultStruct.new(
          result: Billing::Public::ResultStruct.new(
            success: false,
            errors: ["Cannot cancel IAP subscription without explicitly overriding it."]
          )
        )
      end

      validate_purchases_allowed if increased_quantity?

      if cancelling_free_plan?
        update_or_create_subscription_item
      elsif reactivating?
        update_or_create_subscription_item
        schedule_pending_change
      elsif cancel_scheduled_seats_downgrade_or_cancellation?
        T.must(existing_pending_subscription_item_change).destroy!
        update_or_create_subscription_item
      elsif cancel_existing_sponsorship_cancellation?
        T.must(existing_pending_sponsorship_cancellation).destroy!
        update_or_create_subscription_item
      elsif schedule_change?
        schedule_pending_change
      else
        purge_when_cancelling_iap_subscriptions
        update_or_create_subscription_item
        update_pending_change
        if handle_missing_pending_change_for_trial_cancellation?
          result = handle_missing_pending_change_for_trial_cancellation
          if !result
            return Billing::Public::SubscriptionItems::ResultStruct.new(
              result: Billing::Public::ResultStruct.new(success: false, errors: ["Failed to end trial with missing pending change. Please try again."])
            )
          end
        end
      end

      if save_and_validate_items
        synchronize_plan_subscription unless @skip_sync
        send_purchase_webhook unless @pending_change_scheduled
        send_change_webhook if @pending_change_scheduled && !cancelling?

        if update_sponsorship
          instrument_change

          return Billing::Public::SubscriptionItems::ResultStruct.new(
            result: Billing::Public::ResultStruct.new(success: true),
            subscription_item: subscription_item,
            change_scheduled: @pending_change_scheduled
          )
        end
      else
        update_sponsorship
      end

      Billing::Public::SubscriptionItems::ResultStruct.new(
        result: Billing::Public::ResultStruct.new(success: false, errors: item_and_sponsorship_errors)
      )
    rescue StandardError => e # rubocop:todo Lint/GenericRescue
      GitHub.logger.error(
        "Error while updating subscription item: #{e.message}",
        "code.namespace": self.class.name,
        "code.function": "perform",
        "gh.billing.account.id": account&.id,
        "gh.billing.subscription_item.id": @subscription_item&.id,
        "gh.billing.subscription_item.quantity": @subscription_item&.quantity,
        "gh.billing.subscription_item.free_trial_ends_on": @subscription_item&.free_trial_ends_on
      )
      raise e
    end

    private

    sig { returns T.nilable(Billing::Types::Account) }
    attr_reader :account

    sig { returns Billing::PlanSubscription }
    attr_reader :plan_subscription

    sig { returns(T::Boolean) }
    attr_reader :force
    sig { returns(T::Array[String]) }
    attr_reader :sponsorship_errors

    sig { returns(Integer) }
    attr_reader :previous_quantity

    sig { returns(Integer) }
    attr_reader :quantity

    sig { returns(T.nilable(User)) }
    attr_reader :sender

    sig { returns(T::Boolean) }
    attr_reader :start_free_trial

    sig { returns(T::Boolean) }
    attr_reader :end_free_trial

    sig { returns(T.nilable(Date)) }
    attr_reader :free_trial_ends_on

    sig { returns(T::Boolean) }
    attr_reader :previously_on_free_trial

    sig { returns(T.nilable(Date)) }
    attr_reader :previous_free_trial_ends_on

    sig { returns(T.nilable(Organization)) }
    attr_reader :organization

    sig { returns(T::Boolean) }
    attr_reader :allow_cancelling_iap

    sig { returns(T.nilable(Billing::Public::InAppPurchase)) }
    attr_reader :in_app_purchase

    sig { returns T.nilable(Billing::SubscriptionItem) }
    attr_accessor :old_subscription_item

    sig { params(subscription_item: Billing::SubscriptionItem).void }
    attr_writer :subscription_item

    sig { returns(Billing::SubscriptionItem) }
    def subscription_item
      T.must_because(@subscription_item) { "#perform returns early when subscription item is nil" }
    end

    sig { returns(T::Boolean) }
    attr_accessor :invalidate_free_trials

    sig { returns T.any(Billing::Types::Subscribable, Billing::ProductUUID) }
    attr_reader :subscribable, :previous_subscribable

    delegate :listing, to: :subscribable

    # Internal: Checks if the subscription_item being "updated" is a sponsorable
    # item, and then whether the quantity and subscribable are unchanged.
    #
    # If nothing changed, we don't want to instrument.
    # This happens when a user updates the privacy setting on a sponsorship.
    # That will be captured in Hydro, but its not a "plan change" as Transaction
    # records are used for.
    #
    # Returns: Boolean
    sig { returns(T::Boolean) }
    def nothing_changed_for_sponsorable_item?
      subscription_item.subscribable_SponsorsTier? &&
        quantity == previous_quantity &&
        subscribable == previous_subscribable
    end

    # We do not want to keep IAP records around for cancelled subscription item records.
    sig { void }
    def purge_when_cancelling_iap_subscriptions
      return unless cancelling?

      subscription_item.destroy_in_app_purchase_subscriptions!
    end

    sig { void }
    def update_free_trial
      if free_trial_ends_on.present?
        subscription_item.free_trial_ends_on = free_trial_ends_on
      elsif subscription_item.on_free_trial? && end_free_trial == true
        subscription_item.free_trial_ends_on = GitHub::Billing.yesterday
      end
    end

    sig { params(from: T.nilable(Billing::SubscriptionItem), to: Billing::SubscriptionItem).void }
    def transfer_free_trial(from: old_subscription_item, to: subscription_item)
      @start_free_trial = true
      to.free_trial_ends_on = from&.free_trial_ends_on
      schedule_pending_change
    end

    sig { returns(T.nilable(Billing::SubscriptionItem)) }
    def find_subscription_item
      subscribable = self.subscribable
      if subscribable.is_a?(Billing::ProductUUID)
        # Find subscription items by product type, not specific charge.
        # For updates, match by product type only to allow upgrades within the same product family.
        # For cancellations, match by both product type and key to avoid cancelling the wrong item.
        product_uuids = Billing::ProductUUID.where(product_type: subscribable.product_type)
        product_uuids = product_uuids.where(product_key: subscribable.product_key) if cancelling?
        uuid_ids = product_uuids.pluck(:id)

        items = if @include_inactive
          plan_subscription.subscription_items
        else
          plan_subscription.active_subscription_items
        end

        items.where(subscribable_type: Billing::ProductUUID.name)
          .where(subscribable_id: uuid_ids)
          .first
      elsif subscribable.is_a?(Marketplace::ListingPlan)
        plan_subscription.subscription_item_for_marketplace_listing(listing, organization: organization)
      elsif subscribable.is_a?(SponsorsTier)
        plan_subscription.subscription_item_for_sponsors_listing(listing,
          subscribable: subscribable,
          organization: organization
        )
      end
    end

    sig { returns(T.nilable(Billing::SubscriptionItem)) }
    def cancelled_subscription_item
      plan_subscription.past_subscription_items.where(subscribable: subscribable).first
    end

    sig { void }
    def update_or_create_subscription_item
      if subscription_item.subscribable == subscribable
        self.old_subscription_item = nil
        subscription_item.quantity = quantity
        update_free_trial
      else
        old_sub_item = self.old_subscription_item = subscription_item
        old_sub_item.quantity = 0

        # TODO: This code is specific for marketplace installations
        # We'll want to figure out how to move this out of here
        # to decouple marketplaces from subscription items
        if old_sub_item.listing
          integration_installation = IntegrationInstallation.find_by(target: account,
            integration: old_sub_item.listable)
          installed_at = integration_installation&.created_at
          old_sub_item.installed_at = nil
        end

        cancelled_sub_item = cancelled_subscription_item
        if cancelled_sub_item
          self.subscription_item = cancelled_sub_item
          subscription_item.quantity = quantity
          subscription_item.installed_at = installed_at
        else
          self.subscription_item = ::Billing::SubscriptionItem.new \
            subscribable: subscribable,
            quantity: quantity,
            installed_at: installed_at,
            plan_subscription: plan_subscription,
            organization: organization
        end

        # TODO: This code is specific for marketplace installations
        # We'll want to figure out how to move this out of here
        # to decouple marketplaces from subscription items
        if old_sub_item.listing
          subscription_item.is_installation_update_req = true
          subscription_item.installation = integration_installation
        end

        old_pending_item_change = old_pending_subscription_item_change
        old_pending_plan_change = old_pending_subscription_item_change&.pending_plan_change
        old_pending_item_change.destroy if old_pending_item_change && old_pending_item_change.free_trial
        old_pending_plan_change.destroy if old_pending_plan_change && !old_pending_plan_change.has_changes?

        if old_sub_item.on_free_trial?
          if !end_free_trial && (subscribable.has_free_trial? || subscribable.is_a?(Billing::ProductUUID))
            transfer_free_trial
          else
            self.invalidate_free_trials = true
            old_sub_item.free_trial_ends_on = GitHub::Billing.yesterday
          end
        end

        if subscription_item.eligible_for_free_trial? && !@pending_change_scheduled
          @start_free_trial = true
          schedule_pending_change
        end
      end

      # If a new IAP object was passed in then we need to associate it with the new subscription item.
      subscription_item.build_in_app_purchase_association(T.must(in_app_purchase)) if in_app_purchase
    end

    sig { returns(T::Boolean) }
    def increased_quantity?
      quantity > subscription_item.quantity
    end

    sig { void }
    def validate_purchases_allowed
      account = self.account
      raise ::Platform::Errors::Unprocessable.new("Account not found") if account.blank?
      result = account.validate_purchases_allowed(actor: sender, check_dunning: true)
      raise ::Platform::Errors::Unprocessable.new(result.error_message) if result.failed?
    end

    sig { returns(T::Boolean) }
    def save_and_validate_items
      ::Billing::SubscriptionItem.transaction do
        # Skip the automatic external subscription update - for synchronous payments,
        # the first synchronization must be run from CollectPaymentOnUpgradeJob.
        subscription_item.skip_sync = true
        old_sub_item = old_subscription_item
        old_item_valid = if old_sub_item
          old_sub_item.skip_sync = true
          old_sub_item.save
        else
          true
        end

        # We need to now reconcile our in-app purchasing records across affected records.
        # If we have an old record, then we need to indicate their IAP records are to be destroyed upon saving.
        if old_sub_item&.in_app_purchase? && old_sub_item.quantity == 0
          old_sub_item.destroy_in_app_purchase_subscriptions!
        end

        # If an IAP record was passed in then saving this should also persist the associated IAP record.
        item_valid = subscription_item.save

        success = old_item_valid && item_valid
        cancel_free_trials if success && invalidate_free_trials

        success
      end
    end

    sig { returns(T.nilable(Integer)) }
    def cancel_free_trials
      subscribable = self.subscribable
      return unless subscribable.is_a?(Marketplace::ListingPlan)

      # NOTE: only marketplace offers free trials, so the scope/_id here are as yet unchanged
      listing_plans_ids = Marketplace::ListingPlan.where(
        marketplace_listing_id: subscribable.marketplace_listing_id,
      ).pluck(:id)

      free_trial_ids = plan_subscription
        .subscription_items
        .for_marketplace_listing_plans(listing_plans_ids)
        .where("free_trial_ends_on IS NOT NULL")
        .pluck(:id)

      plan_subscription
        .subscription_items
        .where(id: free_trial_ids)
        .update_all(free_trial_ends_on: GitHub::Billing.yesterday)
    end

    sig { void }
    def send_purchase_webhook
      return if subscription_item.subscribable.is_a?(Billing::ProductUUID)
      GitHub.instrument "#{event_prefix}.#{purchase_event_type}",
        subscription_item_id: subscription_item.id,
        sender_id: sender&.id,
        previous_quantity: previous_quantity,
        previously_on_free_trial: previously_on_free_trial,
        previous_free_trial_ends_on: previous_free_trial_ends_on,
        previous_subscribable_id: previous_subscribable.id,
        previous_subscribable_type: previous_subscribable.class.name
    end

    sig { void }
    def send_change_webhook
      return if subscription_item.subscribable.is_a?(Billing::ProductUUID)
      # nb: the item_change can be missing if the plan change already ran
      return unless pending_subscription_item_change

      GitHub.instrument "#{event_prefix}.pending_change",
        sender_id: sender&.id,
        pending_subscription_item_change_id: pending_subscription_item_change&.id,
        subscription_item_id: subscription_item.id
    end

    sig { returns(T::Array[String]) }
    def item_and_sponsorship_errors
      messages = [old_subscription_item_error_message, new_subscription_item_error_message, sponsorship_error_message]
      messages.reject(&:blank?).uniq
    end

    sig { returns(String) }
    def old_subscription_item_error_message
      return "" unless old_subscription_item
      T.must(old_subscription_item).errors.full_messages.join(", ")
    end

    sig { returns(String) }
    def new_subscription_item_error_message
      subscription_item.errors.full_messages.join(", ")
    end

    sig { returns(String) }
    def sponsorship_error_message
      sponsorship_errors.join(", ")
    end

    sig { returns(T::Boolean) }
    def is_downgrade?
      return true if cancelling_active?
      sub_item_price = subscription_item.price
      subscribable = self.subscribable
      copilot_always_upgrade_to_pro_plus_immediately_feature_enabled = sender&.feature_enabled?(:copilot_always_upgrade_to_pro_plus_immediately) ||
        GitHub.flipper[:copilot_always_upgrade_to_pro_plus_immediately].enabled?
      if subscribable.is_a?(Billing::ProductUUID) && copilot_always_upgrade_to_pro_plus_immediately_feature_enabled
        old_subscribable = T.cast(previous_subscribable, Billing::ProductUUID)

        # Changes to a different product in the same product family need to be compared using the same billing cycle.
        # This ensures we upgrade immediately to a higher-tier product, even if the cost is lower due to the billing cycle.
        duration = if old_subscribable.product_type == subscribable.product_type &&
            old_subscribable.product_key != subscribable.product_key
          old_subscribable.billing_cycle
        else
          subscribable.billing_cycle
        end

        sub_item_price > plan_price(duration: duration)
      elsif subscribable.is_a?(SponsorsTier)
        sub_item_price >= plan_price
      else
        sub_item_price > plan_price
      end
    end

    sig { returns(T.nilable(Billing::PendingSubscriptionItemChange)) }
    def existing_pending_subscription_item_change
      return unless account
      T.must(account).pending_subscription_item_changes.for_product_type_product_uuid_subscribable(subscribable)&.last
    end

    sig { returns(T::Boolean) }
    def cancel_scheduled_seats_downgrade_or_cancellation?
      (account.is_a?(Business) || account.is_a?(Organization)) && subscribable.is_a?(Billing::ProductUUID) &&
        subscription_item.quantity <= quantity && existing_pending_subscription_item_change.present?
    end

    sig { returns(T::Boolean) }
    def cancel_existing_sponsorship_cancellation?
      return false unless force
      return false unless subscribable.is_a?(SponsorsTier)
      return false unless cancelling?
      existing_pending_sponsorship_cancellation.present?
    end

    sig { returns(T.nilable(Billing::PendingSubscriptionItemChange)) }
    memoize def existing_pending_sponsorship_cancellation
      existing_change = subscription_item.pending_subscription_item_change
      return unless existing_change&.cancellation?
      existing_change
    end

    sig { params(duration: T.nilable(String)).returns(Billing::Money) }
    def plan_price(duration: nil)
      if subscribable.is_a?(Billing::ProductUUID)
        subscribable.base_price(duration: duration || subscribable.billing_cycle) * quantity
      else
        duration ||= account&.plan_duration || subscribable.try(:billing_cycle) || User::BillingDependency::MONTHLY_PLAN
        subscribable.base_price(duration: duration) * quantity
      end
    end

    sig { void }
    def schedule_pending_change
      return unless account
      required_account = T.must(account)
      @pending_change_scheduled = true
      SchedulePlanChange.run \
        account: required_account,
        actor: T.must(sender),
        active_on: change_effective_date,
        free_trial: start_free_trial,
        subscribable: subscribable,
        subscribable_quantity: quantity,
        plan_subscription: plan_subscription,
        organization: organization
    end

    sig { returns(T.nilable(Billing::PendingSubscriptionItemChange)) }
    memoize def pending_subscription_item_change
      subscribable = self.subscribable
      subscribable_supports_org_mgmt_delegation = subscribable.is_a?(Marketplace::ListingPlan) ||
        subscribable.is_a?(SponsorsTier)
      if subscribable_supports_org_mgmt_delegation && subscribable.management_delegated_to_org?(account)
        subscribable.pending_subscription_item_change(account: account, organization: organization)
      else # Billing::ProductUUID
        subscribable.pending_subscription_item_change(account: account)
      end
    end

    sig { returns(T.nilable(Billing::PendingSubscriptionItemChange)) }
    def old_pending_subscription_item_change
      account = self.account
      old_sub_item = old_subscription_item
      return unless old_sub_item && account

      account.pending_subscription_item_changes.find_by(subscribable: old_sub_item.subscribable)
    end

    sig { returns(T::Boolean) }
    def handle_missing_pending_change_for_trial_cancellation?
      return false unless cancelling_trial?
      return false if pending_subscription_item_change
      true
    end

    sig { returns(T::Boolean) }
    def handle_missing_pending_change_for_trial_cancellation
      subscription_item.update(free_trial_ends_on: GitHub::Billing.yesterday)
    end

    sig { returns(T.nilable(T::Boolean)) }
    def update_pending_change
      return unless account&.incomplete_pending_plan_changes.present? && pending_subscription_item_change
      required_pending_subscription_item_change = T.must(pending_subscription_item_change)

      if cancelling_trial?
        trial_pending_plan_change = required_pending_subscription_item_change.pending_plan_change
        Billing::SubscriptionItem.transaction do
          trial_pending_plan_change&.destroy
          if account&.feature_enabled?(:billing_skip_sync_when_cancelling_subscription_item_trial)
            # Use `update_column` to skip callbacks since we will trigger all callbacks when we
            # formally save the subscription item later in the subscription item update process.
            subscription_item.update_column(:free_trial_ends_on, GitHub::Billing.yesterday)
          else
            subscription_item.update(free_trial_ends_on: GitHub::Billing.yesterday)
          end
        end
      else
        required_pending_subscription_item_change.update_attribute :quantity, quantity
      end
    end

    sig { returns(String) }
    def purchase_event_type
      quantity > 0 ? "changed" : "cancelled"
    end

    sig { returns(String) }
    def event_prefix
      if subscription_item.subscribable_SponsorsTier?
        "sponsorship"
      else
        "marketplace_purchase"
      end
    end

    sig { returns(T::Boolean) }
    def cancelling_free_plan?
      cancelling? && !subscription_item.subscribable.paid?
    end

    sig { returns(T::Boolean) }
    def reactivating?
      @include_inactive && quantity > 0
    end

    sig { returns(T::Boolean) }
    def schedule_change?
      !force && (is_downgrade? || start_free_trial)
    end

    sig { returns(T::Boolean) }
    def subscription_item_changed?
      !!(old_subscription_item.present? && subscription_item != old_subscription_item)
    end

    sig { returns(T::Boolean) }
    def cancelling_trial?
      cancelling? && subscription_item.on_free_trial? # #on_free_trial? checks whether `free_trial_ends_on` is nil
    end

    sig { returns(T::Boolean) }
    def cancelling_active?
      cancelling? && !subscription_item.on_free_trial?
    end

    sig { returns(T::Boolean) }
    def cancelling?
      quantity == 0
    end

    # Date on which a schedule plan change should execute
    # SchedulePlanChange will set a default date when this method returns
    # nil
    #
    # @return [Date] or nil
    sig { returns(T.nilable(Date)) }
    def change_effective_date
      if start_free_trial && subscription_item.on_free_trial?
        # #on_free_trial? ensures non-nil free_trial_ends_on
        subscription_item.free_trial_ends_on + 1.day
      elsif subscription_item.subscribable_Billing_ProductUUID?
        if cancelling_trial?
          # #cancelling_trial? ensures non-nil free_trial_ends_on
          subscription_item.free_trial_ends_on + 1.day
        else
          # We're downgrading a UUID prouct so we use it's subscription
          # item to determine the change date
          subscription_item.next_billing_date
        end
      elsif subscribable.is_a?(SponsorsTier)
        account&.next_sponsors_billing_date
      else
        account&.next_billing_date
      end
    end

    sig { void }
    def instrument_change
      user = T.must(account) if account&.user?
      business = T.must(account) if account&.business?
      subscribable = self.subscribable
      context = {
        actor: sender,
        actor_id: sender&.id,
        business: business,
        business_id: business&.id,
        user: user,
        user_id: user&.id,
      }

      if cancelling? || previous_subscribable != subscribable
        instrument_change_for_sponsors if subscription_item.subscribable_SponsorsTier?

        GlobalInstrumenter.instrument(
          "billing.subscription_item_change",
          context.merge(
            old_subscribable: previous_subscribable,
            old_quantity: previous_quantity,
            new_subscribable: subscribable,
            new_quantity: quantity,
          )
        )
      elsif previous_quantity != quantity
        GlobalInstrumenter.instrument(
          "billing.subscription_item_quantity_change",
          context.merge(
            subscribable: subscribable,
            old_quantity: previous_quantity,
            new_quantity: quantity,
          )
        )
      end

      if end_free_trial
        GlobalInstrumenter.instrument(
          "billing.free_trial_conversion",
          context.merge(
            subscribable: subscribable,
            quantity: quantity,
          )
        )
      end

      # Audit logging for ProductUUID-based subscription items
      # Other subscription items (e.g. Sponsors and Marketplace) have their own separate logging
      if !@pending_change_scheduled && subscribable.is_a?(Billing::ProductUUID)
        # Reconstitute the InAppPurchase object which contains the associated vendor data we store on our side.
        # If this is null then it means the subscription was not created via an in-app purchase.
        in_app_purchase = subscription_item.in_app_purchase

        # The old subscribable should also be a Billing::ProductUUID
        old_subscribable = T.cast(previous_subscribable, Billing::ProductUUID)

        payload = context.merge(
          sender_id: sender&.id,
          subscription_item_id: subscription_item.id,
          old_free_trial_ends_on: previous_free_trial_ends_on,
          old_quantity: previous_quantity,
          old_subscribable_id: previous_subscribable.id,
          old_subscribable_type: previous_subscribable.class.name,
          old_product_type: old_subscribable.product_type,
          old_product_key: old_subscribable.product_key,
          old_billing_cycle: old_subscribable.billing_cycle,
          new_free_trial_ends_on: subscription_item.free_trial_ends_on,
          new_quantity: quantity,
          new_subscribable_id: subscribable.id,
          new_subscribable_type: subscribable.class.name,
          new_product_type: subscribable.product_type,
          new_product_key: subscribable.product_key,
          new_billing_cycle: subscribable.billing_cycle,
          in_app_purchase_vendor: in_app_purchase&.type&.serialize,
          in_app_purchase_identifier: in_app_purchase&.identifier,
        )

        if cancelling?
          GitHub.instrument("billing.subscription_item_cancelled", payload)
        else
          GitHub.instrument("billing.subscription_item_changed", payload)
        end
      end
    end

    sig { void }
    def instrument_change_for_sponsors
      return unless sponsorship = subscription_item.sponsorship

      previous_tier = T.cast(previous_subscribable, T.nilable(SponsorsTier))

      if @pending_change_scheduled
        new_tier = unless cancelling?
          T.cast(subscribable, T.nilable(SponsorsTier))
        end
        # A sponsorship downgrade or cancellation was scheduled for the
        # beginning of the sponsor's next billing cycle.
        sponsorship.instrument_pending_change(actor: sender, old_tier: previous_tier, new_tier: new_tier)

        if cancelling?
          sponsorship.instrument_cancelling(
            actor: sender,
            pending_change_on: pending_subscription_item_change&.active_on
          )
        else
          sponsorship.instrument_pending_tier_change(
            actor: sender,
            pending_subscription_item_change: pending_subscription_item_change
          )
        end
      elsif cancelling?
        # The sponsorship was either force-cancelled or cancelled via a previously
        # scheduled pending change.
        sponsorship.instrument_cancel(actor: sender)
      else
        # The sponsorship was either upgraded via a successful prorated transaction
        # or downgraded via a previously scheduled pending change.
        sponsorship.instrument_tier_change(actor: sender, previous_tier: previous_tier)
      end
    end

    # Private: Returns a Boolean indicating success.
    sig { returns(T::Boolean) }
    def update_sponsorship
      return true unless subscription_item.subscribable_SponsorsTier?
      return true if @pending_change_scheduled

      # The organization field is passed from the subscription item, and it's used to disambiguate the managing
      # entity when it differs from the billable entity. In the case of Sponsors, an enterprise account
      # may be billed, but a member organization is still the sponsor so we prefer the organization if it exists.
      sponsor = organization || account
      sponsorable = subscription_item.sponsorable

      # Can't use `subscription_item.sponsorship` relation because that's what we're trying to update, to swap out
      # the `subscription_item_id` on the sponsorship to point to the new one:
      sponsorship = Sponsorship.from_sponsor(sponsor).with_user_or_org_sponsorable(sponsorable).first

      return true if sponsorship.nil?

      subscription_item_to_sync = if subscription_item.errors.empty?
        subscription_item
      else
        old_subscription_item
      end
      return true unless subscription_item_to_sync

      sponsorship.update_subscription_item(subscription_item_to_sync)
      true
    rescue ActiveRecord::RecordInvalid => err
      sponsorship_errors.concat(T.must(sponsorship).errors.full_messages)
      false
    end

    sig { void }
    def synchronize_plan_subscription
      should_collect_payment_immediately = account&.collect_payment_immediately_for_plan_or_seat_changes?\
        && subscription_item.subscribable_Billing_ProductUUID?\
        && !subscription_item.on_free_trial?\
        && subscription_item.billable?
      if should_collect_payment_immediately
        account = T.must(self.account)

        CollectPaymentForUpgradeJob.perform_later(
          billable_entity: account,
          old_plan_name: account.plan.name,
          old_seat_count: account.seats,
          notify_on_failure: true,
          actor: sender,
          subscription_item: @subscription_item,
          old_subscription_item_quantity: old_subscription_item&.quantity || @previous_quantity,
        )
      else
        plan_subscription.synchronize_later
      end
    end
  end
end
