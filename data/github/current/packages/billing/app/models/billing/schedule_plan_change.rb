# typed: strict
# frozen_string_literal: true

module Billing
  class SchedulePlanChange

    include GitHub::Memoizer

    sig do
      params(
        account: ::Billing::Types::Account,
        actor: User,
        seats: T.nilable(Integer),
        plan: T.nilable(T.any(String, GitHub::Plan)),
        plan_duration: T.nilable(String),
        data_packs: T.nilable(Integer),
        subscribable: T.nilable(T.any(::Billing::ProductUUID, Billing::Types::Subscribable)),
        subscribable_quantity: T.nilable(Integer),
        active_on: T.nilable(T.any(Date, Time, ActiveSupport::TimeWithZone)),
        free_trial: T::Boolean,
        schedule_at: T.nilable(Time),
        plan_subscription: T.nilable(Billing::PlanSubscription),
        organization: T.nilable(Organization)
      ).returns(GitHub::Billing::Result)
    end
    def self.run(account:, actor:, seats: nil, plan: nil, plan_duration: nil, data_packs: nil, subscribable: nil, subscribable_quantity: nil, active_on: nil, free_trial: false, schedule_at: nil, plan_subscription: nil, organization: nil)
      new(
        account: account,
        actor: actor,
        seats: seats,
        plan: plan,
        plan_duration: plan_duration,
        data_packs: data_packs,
        subscribable: subscribable,
        subscribable_quantity: subscribable_quantity,
        active_on: active_on,
        free_trial: free_trial,
        schedule_at: schedule_at,
        plan_subscription: plan_subscription,
        organization: organization
      ).run
    end

    BILLING_CYCLE_BUFFER_TIME = T.let(30.minutes, ActiveSupport::Duration)

    sig do
      params(
        account: ::Billing::Types::Account,
        actor: User,
        seats: T.nilable(Integer),
        plan: T.nilable(T.any(String, GitHub::Plan)),
        plan_duration: T.nilable(String),
        data_packs: T.nilable(Integer),
        subscribable: T.nilable(T.any(::Billing::ProductUUID, Billing::Types::Subscribable)),
        subscribable_quantity: T.nilable(Integer),
        active_on: T.nilable(T.any(Date, Time, ActiveSupport::TimeWithZone)),
        free_trial: T::Boolean,
        schedule_at: T.nilable(Time),
        plan_subscription: T.nilable(Billing::PlanSubscription),
        organization: T.nilable(Organization)
      ).void
    end
    def initialize(account:, actor:, seats: nil, plan: nil, plan_duration: nil, data_packs: nil, subscribable: nil, subscribable_quantity: nil, active_on: nil, free_trial: false, schedule_at: nil, plan_subscription: nil, organization: nil)
      @account = account
      @actor = actor
      @active_on = T.let(active_on || next_billing_date(subscribable),
        T.nilable(T.any(Date, Time, ActiveSupport::TimeWithZone)))
      @free_trial = free_trial
      @data_packs = data_packs
      @plan = plan
      @plan_duration = plan_duration
      @seats = seats
      @subscribable = subscribable
      @subscribable_quantity = subscribable_quantity
      @schedule_at = schedule_at
      @plan_subscription = plan_subscription
      @organization = organization
    end

    sig { returns(GitHub::Billing::Result) }
    def run
      validate_input
      result = T.must(self.result)
      return result if result.failed?

      assign_change_attributes

      if change.save && create_or_update_subscribable_change
        RunPendingPlanChangeJob
          .set(wait_until: schedule_change_at(change))
          .perform_later(change)
        GitHub::Billing::Result.success
      else
        GitHub::Billing::Result.failure error_messages
      end
    end

    private

    sig { params(change: T.nilable(::Billing::PendingPlanChange)).returns(T.nilable(::Billing::PendingPlanChange)) }
    attr_writer :change

    sig { returns(::Billing::Types::Account) }
    attr_accessor :account

    sig { returns(User) }
    attr_accessor :actor

    sig { returns(T.nilable(Integer)) }
    attr_accessor :data_packs

    sig { returns(T.nilable(T.any(::Billing::ProductUUID, ::Billing::Types::Subscribable))) }
    attr_accessor :subscribable

    sig { returns(T.nilable(Integer)) }
    attr_accessor :subscribable_quantity

    sig { returns(T.nilable(T.any(String, GitHub::Plan))) }
    attr_accessor :plan

    sig { returns(T.nilable(String)) }
    attr_accessor :plan_duration

    sig { returns(T.nilable(GitHub::Billing::Result)) }
    attr_accessor :result

    sig { returns(T.nilable(Integer)) }
    attr_accessor :seats

    sig { returns(T::Boolean) }
    attr_accessor :free_trial

    sig { returns(::Billing::PendingPlanChange) }
    def change
      @change ||= T.let(
        if free_trial && !similar_pending_subscription_item_changes?
          account.pending_plan_changes.build
        else
          account.pending_plan_changes.incomplete.where(active_on: @active_on).first || account.pending_plan_changes.build
        end, T.nilable(::Billing::PendingPlanChange)
      )
    end

    # Private: Time to schedule RunPendingPlanChangeJob
    # To limit the number of concurrent requests, it adds an arbitary 0-59 second offset.
    sig { params(change: ::Billing::PendingPlanChange).returns(Time) }
    def schedule_change_at(change)
      return @schedule_at if @schedule_at

      offset_seconds = (change.id.to_i % 60).seconds
      (change.active_on + offset_seconds).to_time
    end

    sig { void }
    def assign_change_attributes
      change.plan = plan if changing_plan?
      change.plan_duration = plan_duration if changing_duration?
      if changing_seats? || (changing_plan? && change.plan&.per_seat?)
        change.seats = [seats.to_i, base_seats].max
      end
      change.active_on = @active_on&.to_date
      change.actor = actor
      change.data_packs = data_packs if data_packs
    end

    sig { returns(Integer) }
    def base_seats
      change.plan&.per_seat? ? T.must(change.plan).base_units : 0
    end

    sig { returns(T::Boolean) }
    def changing_plan?
      !!plan && plan != account.plan
    end

    sig { returns(T::Boolean) }
    def changing_seats?
      !!seats && seats != account.seats
    end

    sig { returns(T::Boolean) }
    def changing_duration?
      !!plan_duration && plan_duration != account.plan_duration
    end

    sig { void }
    def validate_input
      if subscribable_quantity && subscribable && subscription_item
        validate_subcribable_input
      else
        validate_plan_input
      end
    end

    sig { void }
    def validate_plan_input
      account = self.account
      if seats = self.seats
        account.seats = seats
      end
      if plan_duration = self.plan_duration
        account.plan_duration = plan_duration
      end
      unless account.is_a?(Business)
        account.plan = plan.to_s
      end

      self.result = account.valid? ? GitHub::Billing::Result.success : invalid_input_error(account)

      account.restore_attributes
    end

    sig { void }
    def validate_subcribable_input
      subscription_item = T.must(self.subscription_item)
      subscription_item.quantity = subscribable_quantity.to_i
      self.result = subscription_item.valid? ? GitHub::Billing::Result.success : invalid_input_error(subscription_item)
    end

    sig { params(model: ApplicationRecord::Base).returns(GitHub::Billing::Result) }
    def invalid_input_error(model)
      GitHub::Billing::Result.failure model.errors.full_messages.to_sentence
    end

    sig { returns(T::Boolean) }
    def create_or_update_subscribable_change
      return true unless subscribable || subscribable_quantity
      pending_subscription_item_change.update \
        free_trial: free_trial || !!pending_subscription_item_change.free_trial,
        subscribable: subscribable,
        quantity: subscribable_quantity,
        organization: @organization
    end

    sig { returns(::Billing::PendingSubscriptionItemChange) }
    def pending_subscription_item_change
      @pending_subscription_item_change ||= T.let(
        begin
          subscribable = T.must(self.subscribable)
          query_scope = change.pending_subscription_item_changes.for_plan_subscription(@plan_subscription)
          query_scope =
            if subscribable.is_a?(Billing::ProductUUID)
              query_scope.for_product_type_product_uuid_subscribable(subscribable)
            else
              if @organization.present?
                query_scope.for_subscribable_listing(subscribable.listing).for_organization(@organization)
              else
                query_scope.for_subscribable_listing(subscribable.listing)
              end
            end
          query_scope.first || change.pending_subscription_item_changes.build(subscribable: subscribable, plan_subscription: @plan_subscription, organization: @organization)
        end, T.nilable(::Billing::PendingSubscriptionItemChange)
      )
    end

    sig { returns(T::Boolean) }
    def similar_pending_subscription_item_changes?
      if subscribable.is_a?(Billing::ProductUUID)
        account
          .pending_subscription_item_changes
          .joins(:pending_plan_change)
          .where(pending_plan_change: { active_on: @active_on })
          .for_plan_subscription(@plan_subscription)
          .for_product_type_product_uuid_subscribable(subscribable).exists?
      else
        # Not yet implemented for this subscribable type
        false
      end
    end

    sig { returns(T.nilable(String)) }
    def error_messages
      change.errors.full_messages.to_sentence
    end

    sig do
      params(
        subscribable: T.nilable(T.any(::Billing::ProductUUID, ::Billing::Types::Subscribable))
      ).returns(T.nilable(Date))
    end
    def next_billing_date(subscribable)
      case subscribable
      when SponsorsTier
        account.next_sponsors_billing_date
      else
        account.next_billing_date
      end
    end

    sig { returns(T.nilable(::Billing::SubscriptionItem)) }
    memoize def subscription_item
      return unless @plan_subscription
      @plan_subscription.active_subscription_items.reload.find do |subscription_item|
        subscription_item.subscribable == subscribable
      end
    end
  end
end
