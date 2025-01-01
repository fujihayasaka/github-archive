# typed: strict
# frozen_string_literal: true

module Billing
  # Provides functionality for collecting payment for a plan/seat upgrade by synchronizing the plan subscription with
  # Zuora and immediately charging for invoices that are due. On payment failures, a rollback can be performed to
  # revert the plan subscription back to the old plan/seats.
  #
  # Important: When using this class, the caller is responsible for ensuring that the Zuora subscription has not been
  # synchronized with the new plan/seats yet. If Zuora already has the new plan/seat information, no payment collection
  # will be deemed necessary by Zuora and thus the payment collection will be assumed to be successful.
  #
  class CollectPaymentForUpgrade
    extend T::Sig

    sig do
      params(
        plan_subscription: PlanSubscription,
        old_plan: GitHub::Plan,
        old_seat_count: Integer,
        actor: T.nilable(User),
        subscription_item: T.nilable(Billing::SubscriptionItem),
        old_subscription_item_quantity: T.nilable(Integer)
      ).returns(GitHub::Billing::Result)
    end
    def self.synchronize(plan_subscription, old_plan, old_seat_count, actor = nil, subscription_item = nil, old_subscription_item_quantity = nil)
      new(plan_subscription, old_plan, old_seat_count, actor, subscription_item, old_subscription_item_quantity).synchronize
    end

    sig do
      params(
        plan_subscription: PlanSubscription,
        old_plan: GitHub::Plan,
        old_seat_count: Integer,
        actor: T.nilable(User),
        subscription_item: T.nilable(Billing::SubscriptionItem),
        old_subscription_item_quantity: T.nilable(Integer),
        reason: String
      ).void
    end
    def self.rollback(plan_subscription, old_plan, old_seat_count, actor = nil, subscription_item = nil, old_subscription_item_quantity = nil, reason: DEFAULT_ROLLBACK_REASON)
      new(plan_subscription, old_plan, old_seat_count, actor, subscription_item, old_subscription_item_quantity).rollback(reason)
    end

    sig do
      params(
        plan_subscription: PlanSubscription,
        old_plan: GitHub::Plan,
        old_seat_count: Integer,
        actor: T.nilable(User),
        subscription_item: T.nilable(Billing::SubscriptionItem),
        old_subscription_item_quantity: T.nilable(Integer),
        message: String
      ).void
    end
    def self.send_failure_notification(plan_subscription, old_plan, old_seat_count, actor = nil, subscription_item = nil, old_subscription_item_quantity = nil, message: DEFAULT_NOTIFICATION_MESSAGE)
      new(plan_subscription, old_plan, old_seat_count, actor, subscription_item, old_subscription_item_quantity).send_failure_notification(message)
    end

    sig { returns(::Billing::PlanSubscription) }
    attr_reader :plan_subscription

    sig { returns(GitHub::Plan) }
    attr_reader :old_plan

    sig { returns(Integer) }
    attr_reader :old_seat_count

    sig { returns(T.nilable(User)) }
    attr_reader :actor

    sig { returns(T.nilable(Billing::SubscriptionItem)) }
    attr_reader :subscription_item

    sig { returns(T.nilable(Integer)) }
    attr_reader :old_subscription_item_quantity

    DEFAULT_ROLLBACK_REASON = "payment collection failed"
    DEFAULT_NOTIFICATION_MESSAGE = "There was an issue processing your payment method."

    delegate \
      :billable_business?,
      :billable_entity,
      :billable_user?,
      :business,
      :plan,
      :seats,
      :user,
      to: :plan_subscription

    # Initialize a new CollectPaymentForUpgrade
    #
    # plan_subscription                 - The plan subscription to collect payment for
    # old_plan                          - The old plan to rollback to
    # old_seat_count                    - The old seat count to rollback to
    # actor                             - The (optional) user performing the upgrade
    # subscription_item                 - The (optional) Billing::SubscriptionItem to collect payment for
    # old_subscription_item_quantity    - The (optional) old Billing::SubscriptionItem quantity to rollback to
    sig do
      params(
        plan_subscription: PlanSubscription,
        old_plan: GitHub::Plan,
        old_seat_count: Integer,
        actor: T.nilable(User),
        subscription_item: T.nilable(Billing::SubscriptionItem),
        old_subscription_item_quantity: T.nilable(Integer)
      ).void
    end
    def initialize(plan_subscription, old_plan, old_seat_count, actor = nil, subscription_item = nil, old_subscription_item_quantity = nil)
      @plan_subscription = plan_subscription
      @old_plan = old_plan
      @old_seat_count = old_seat_count
      @actor = actor
      @subscription_item = subscription_item
      @old_subscription_item_quantity = old_subscription_item_quantity
    end

    # Public: Synchronize the plan subscription and collect payment for plan changes
    sig { returns(GitHub::Billing::Result) }
    def synchronize
      start = Time.now.to_f
      # Reload plan subscription so that it has the latest updates (e.g. seat number)
      plan_subscription.reload
      # Check if we should set the collect param to true, otherwise, it should be nil
      if plan != old_plan || seats != old_seat_count || subscription_item&.quantity != old_subscription_item_quantity
        collect = true
      end
      result = plan_subscription.synchronize_with_lock(collect: collect)
    ensure
      elapsed_ms = (Time.now.to_f - T.must(start)) * 1_000
      track_synchronize(collect, result&.success?, elapsed_ms)
    end

    # Public: Rollback the plan and seat upgrade
    sig { params(reason: String).void }
    def rollback(reason = DEFAULT_ROLLBACK_REASON)
      return unless plan.paid?
      plan_or_seats_changed = plan != old_plan || seats != old_seat_count
      subscription_item_quantity_changed = subscription_item&.quantity != old_subscription_item_quantity
      return unless plan_or_seats_changed || subscription_item_quantity_changed

      # Save the current plan information before we rollback so we can track it
      from_plan = plan
      from_seats = seats
      from_subscription_item_quantity = subscription_item&.quantity
      # Update the plan and seats using `update_columns` to skip the `after_update`
      # callback that would otherwise trigger a synchronization with Zuora.
      if billable_user? && plan_or_seats_changed
        user.update_columns(plan: old_plan.name, seats: old_seat_count)
        user.track_plan_change(user, from_plan, reason: reason)
        user.track_seat_change(user, old_seats: from_seats, reason: reason)
      elsif billable_business? && plan_or_seats_changed
        business.update_column(:seats, old_seat_count)
        business.track_seat_change(from_seats)
      end

      # `force` is set to true because otherwise, a pending subscription change will be created
      #   since the quantity update is considered a downgrade. The subscription should be
      #   canceled immediately.
      # `skip_sync` is set to true because there isn't anything to sync on Zuora's side since the
      #   payment collection failed and thus Zuora did not update the state on their side
      # This same logic applies to the SubscriptionItemUpdater.perform call
      subscription_item = self.subscription_item
      old_subscription_item_quantity = self.old_subscription_item_quantity.to_i
      if subscription_item.present? && old_subscription_item_quantity.zero? && subscription_item.subscribable_Billing_ProductUUID?
        billable_entity.cancel_product_subscription(subscription_item.subscribable, actor: actor, force: true, skip_sync: true)
      elsif subscription_item_quantity_changed
        Billing::SubscriptionItemUpdater.perform(
          quantity: old_subscription_item_quantity,
          sender: actor,
          plan_subscription: plan_subscription,
          subscribable: subscription_item&.subscribable,
          force: true,
          skip_sync: true
        )
      end
      track_rollback(from_plan, from_seats, from_subscription_item_quantity)
    end

    # Public: Notifies the billable entity that the plan/seat upgrade failed
    sig { params(message: String).void }
    def send_failure_notification(message = DEFAULT_NOTIFICATION_MESSAGE)
      if billable_entity.has_paypal_account?
        BillingNotificationsMailer.paypal_failure(billable_entity, message).deliver_later
      else
        BillingNotificationsMailer.cc_failure(billable_entity, message).deliver_later
      end
    end

    private

    # Internal: Tracks the plan/seat synchronization by incrementing
    #           dogstats metrics and logging useful data.
    sig { params(collect: T.nilable(T::Boolean), success: T.nilable(T::Boolean), elapsed_ms: Float).void }
    def track_synchronize(collect, success, elapsed_ms)
      GitHub.dogstats.timing("billing.collect_payment_for_upgrade.synchronize", elapsed_ms, tags: [
        "collect:#{!!collect}",
        "success:#{!!success}",
        "error:#{success.nil?}"
      ])

      GitHub.logger.info(
        "code.namespace" => "Billing::CollectPaymentForUpgrade",
        "code.function" => "synchronize",
        "gh.billing.billable_entity.id" => billable_entity.id,
        "gh.billing.billable_entity.type" => billable_entity.class.name,
        "gh.billing.collect_payment_for_upgrade.collect" => collect,
        "gh.billing.collect_payment_for_upgrade.success" => success,
        "gh.billing.collect_payment_for_upgrade.elapsed_ms" => elapsed_ms
      )
    end

    # Internal: Tracks the plan/seat rollback by incrementing
    #           dogstats metrics and logging useful data.
    sig { params(from_plan: GitHub::Plan, from_seats: Integer, from_subscription_item_quantity: T.nilable(Integer)).void }
    def track_rollback(from_plan, from_seats, from_subscription_item_quantity = nil)
      tags = ["from_plan:#{from_plan}", "to_plan:#{plan}", "from_seats:#{from_seats}", "to_seats:#{seats}"]
      if from_subscription_item_quantity != old_subscription_item_quantity
        tags.concat([
          "from_subscription_item_quantity:#{from_subscription_item_quantity}",
          "to_subscription_item_quantity:#{old_subscription_item_quantity}",
          "subscription_item_name:#{subscription_item&.subscribable_name}"
        ])
      end
      GitHub.dogstats.increment("billing.collect_payment_for_upgrade.rollback", { tags: tags })

      GitHub.logger.info(
        "code.namespace" => "Billing::CollectPaymentForUpgrade",
        "code.function" => "rollback",
        "gh.billing.billable_entity.id" => billable_entity.id,
        "gh.billing.billable_entity.type" => billable_entity.class.name,
        "gh.billing.collect_payment_for_upgrade.from_plan" => from_plan,
        "gh.billing.collect_payment_for_upgrade.to_plan" => plan,
        "gh.billing.collect_payment_for_upgrade.from_seats" => from_seats,
        "gh.billing.collect_payment_for_upgrade.to_seats" => seats,
        "gh.billing.collect_payment_for_upgrade.from_subscription_item_quantity" => from_subscription_item_quantity,
        "gh.billing.collect_payment_for_upgrade.to_subscription_item_quantity" => old_subscription_item_quantity,
        "gh.billing.subscription_item.name" => subscription_item&.subscribable_name
      )
    end
  end
end
