# typed: strict
# frozen_string_literal: true

module Billing
  class PlanSubscription::Synchronizer
    extend T::Sig
    extend T::Helpers

    class ExternalSubscriptionCancellationError < StandardError; end

    abstract!

    sig do
      params(
        plan_subscription: Billing::PlanSubscription,
        set_billing_date_today: T::Boolean,
        synchronization_id: T.nilable(String),
        collect: T.nilable(T::Boolean),
        apply_credit_balance: T.nilable(T::Boolean),
        dogstats_tags: T::Array[String],
        run_billing: T::Boolean,
      ).returns(Billing::PlanSubscription::Synchronizer)
    end
    def self.for_plan_subscription(plan_subscription, set_billing_date_today = true, synchronization_id: nil,
      collect: nil, apply_credit_balance: nil, dogstats_tags: [], run_billing: true)
      Billing::PlanSubscription::ZuoraSynchronizer.new(
        plan_subscription,
        set_billing_date_today,
        synchronization_id: synchronization_id,
        collect: collect,
        apply_credit_balance: apply_credit_balance,
        dogstats_tags: dogstats_tags,
        run_billing: run_billing
      )
    end

    sig do
      params(
        plan_subscription: Billing::PlanSubscription,
        set_billing_date_today: T::Boolean,
        synchronization_id: T.nilable(String),
        collect: T.nilable(T::Boolean),
        apply_credit_balance: T.nilable(T::Boolean),
        dogstats_tags: T::Array[String],
        run_billing: T::Boolean,
      ).returns(GitHub::Billing::Result)
    end
    def self.preview(plan_subscription, set_billing_date_today = true, synchronization_id: nil, collect: nil,
      apply_credit_balance: nil, dogstats_tags: [], run_billing: true)
      for_plan_subscription(
        plan_subscription,
        set_billing_date_today,
        synchronization_id: synchronization_id,
        collect: collect,
        apply_credit_balance: apply_credit_balance,
        dogstats_tags: dogstats_tags,
        run_billing: run_billing
      ).preview
    end

    sig do
      params(
        plan_subscription: Billing::PlanSubscription,
        set_billing_date_today: T::Boolean,
        synchronization_id: T.nilable(String),
        collect: T.nilable(T::Boolean),
        apply_credit_balance: T.nilable(T::Boolean),
        dogstats_tags: T::Array[String],
        run_billing: T::Boolean,
      ).returns(GitHub::Billing::Result)
    end
    def self.update(plan_subscription, set_billing_date_today = true, synchronization_id: nil, collect: nil,
      apply_credit_balance: nil, dogstats_tags: [], run_billing: true)
      for_plan_subscription(
        plan_subscription,
        set_billing_date_today,
        synchronization_id: synchronization_id,
        collect: collect,
        apply_credit_balance: apply_credit_balance,
        dogstats_tags: dogstats_tags,
        run_billing: run_billing
      ).update
    end

    sig do
      params(
        plan_subscription: Billing::PlanSubscription,
        set_billing_date_today: T::Boolean,
        synchronization_id: T.nilable(String),
        collect: T.nilable(T::Boolean),
        apply_credit_balance: T.nilable(T::Boolean),
        dogstats_tags: T::Array[String],
        run_billing: T::Boolean,
      ).returns(GitHub::Billing::Result)
    end
    def self.cancel(plan_subscription, set_billing_date_today = true, synchronization_id: nil, collect: nil,
      apply_credit_balance: nil, dogstats_tags: [], run_billing: true)
      for_plan_subscription(
        plan_subscription,
        set_billing_date_today,
        synchronization_id: synchronization_id,
        collect: collect,
        apply_credit_balance: apply_credit_balance,
        dogstats_tags: dogstats_tags,
        run_billing: run_billing
      ).cancel
    end

    sig do
      params(
        plan_subscription: Billing::PlanSubscription,
        set_billing_date_today: T::Boolean,
        synchronization_id: T.nilable(String),
        collect: T.nilable(T::Boolean),
        apply_credit_balance: T.nilable(T::Boolean),
        dogstats_tags: T::Array[String],
        run_billing: T::Boolean,
      ).returns(GitHub::Billing::Result)
    end
    def self.create(plan_subscription, set_billing_date_today = true, synchronization_id: nil, collect: nil,
      apply_credit_balance: nil, dogstats_tags: [], run_billing: true)
      for_plan_subscription(
        plan_subscription,
        set_billing_date_today,
        synchronization_id: synchronization_id,
        collect: collect,
        apply_credit_balance: apply_credit_balance,
        dogstats_tags: dogstats_tags,
        run_billing: run_billing
      ).create
    end

    # Public: Cancel for a downgrade to free. Generally for internal use, but
    # can be used for user deletes which fully cancel associated plans.
    sig { returns(GitHub::Billing::Result) }
    def cancel_for_downgrade_to_free
      result = Billing::CloseZuoraSubscription.perform(
        zuora_subscription_number: plan_subscription.zuora_subscription_number,
        plan_subscription: plan_subscription
      )
      if result.success?
        user.on_downgrade_to_free
      else
        Failbot.report(
          ExternalSubscriptionCancellationError.new("external subscription failed while downgrading to free"),
          {
            "gh.user.id" => user.id,
            "gh.billing.result.error_message" => result.error_message,
          }
        )
      end
      GitHub.logger.info(
        "code.function" => "cancel_for_downgrade_to_free",
        "gh.billing.result.success" => result.success?
      )

      result
    end

    sig { abstract.returns(::Billing::PlanSubscription) }
    def plan_subscription; end

    sig { abstract.returns(::User) }
    def user; end

    sig { abstract.returns(GitHub::Billing::Result) }
    def preview; end

    sig { abstract.returns(GitHub::Billing::Result) }
    def update; end

    sig { abstract.returns(GitHub::Billing::Result) }
    def cancel; end

    sig { abstract.returns(GitHub::Billing::Result) }
    def create; end

    protected

    sig do
      params(
        plan: GitHub::Plan,
        seats: Integer,
        asset_packs: Integer,
        subscription_items: T::Array[Billing::SubscriptionItem]
      ).returns(Billing::PlanChange)
    end
    def build_plan_change(plan: GitHub::Plan.free, seats: 0, asset_packs: 0, subscription_items: [])
      old_subscription = Billing::Subscription.for_account user,
          plan: plan,
          seats: seats,
          asset_packs: asset_packs,
          subscription_items: subscription_items

      Billing::PlanChange.new old_subscription, user.subscription, starting_new_subscription: !user.external_subscription?
    end
  end
end
