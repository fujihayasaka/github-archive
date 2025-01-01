# typed: strict
# frozen_string_literal: true

module Billing
  class PendingPlanChange < ApplicationRecord::Domain::Integrations

    include Instrumentation::Model
    include GitHub::Memoizer

    belongs_to :user
    belongs_to :actor, class_name: "User"
    belongs_to :customer

    has_many :pending_subscription_item_changes, class_name: "Billing::PendingSubscriptionItemChange", dependent: :destroy
    has_one :plan_trial, class_name: "Billing::PlanTrial"

    validates :active_on, presence: true

    after_update_commit :instrument_updated, if: :incomplete?
    after_create_commit :instrument_creation

    scope :incomplete, -> { where(is_complete: false) }
    scope :not_past, -> { where("active_on >= ?", GitHub::Billing.today) }
    scope :scheduled_for, ->(date) { where(active_on: date) }
    scope :with_seats, -> { where("seats > 0") }
    scope :for_user, -> (user_or_id) { where(user_id: user_or_id) }

    delegate :business, to: :customer, allow_nil: true

    # Returns either a User, Organization or Business associated with the pending plan change.
    sig { returns(T.nilable(::Billing::Types::Account)) }
    def billable_entity
      billable_user? ? user : business
    end

    sig { returns(T::Boolean) }
    def billable_user?
      user.present?
    end

    sig { returns(T::Boolean) }
    def billable_business?
      !billable_user? && business.present?
    end

    # Perform the scheduled plan change
    sig { params(skip_sync: T::Boolean).returns(T::Boolean) }
    def run(skip_sync: false)
      billable_entity = self.billable_entity
      unless billable_entity
        errors.add(:base, "No billable entity on pending plan change")
        return false
      end

      increment!(:attempts)

      if enterprise_cloud_plan_trial_with_coupon?
        EnterpriseCloudTrial.new(user).deactivate!
        return true
      end

      old_plan = billable_entity.plan
      old_seats = billable_entity.seats
      old_plan_duration = billable_entity.plan_duration

      seats = self.seats
      plan = self.plan
      plan_duration = self.plan_duration
      data_packs = self.data_packs

      billable_entity.seats = seats if seats.present?
      billable_entity.plan = plan.to_s if billable_entity.is_a?(User) && plan.present?
      billable_entity.plan_duration = plan_duration if plan_duration.present?
      billable_entity.asset_status&.update_data_packs(
        actor: actor,
        quantity: data_packs,
        force: true
      ) if billable_entity.is_a?(User) && data_packs.present?

      self.plan_changed = T.let(billable_entity.plan_changed?, T.nilable(T::Boolean)) if billable_entity.is_a?(User)
      self.plan_was = T.let(old_plan, T.nilable(GitHub::Plan))
      self.seats_changed = billable_entity.seats_changed?
      self.seats_was = old_seats
      self.plan_duration_changed = billable_entity.plan_duration_changed?
      self.plan_duration_was = old_plan_duration

      if billable_entity.is_a?(User) && billable_entity.apple_iap_subscription?
        self.subscription_provider_was = Billing::PlanSubscription::APPLE_IAP
      end

      # When the plan/seats/duration changes, a subscription synchronization will be scheduled when the billable
      # entity is saved. In this case, we don't need to schedule a synchronization for the subscription item changes.
      skip_sync_for_subscription_item_changes = skip_sync || T.must(plan_changed || seats_changed || plan_duration_changed)
      run_pending_subscription_item_changes(skip_sync: skip_sync_for_subscription_item_changes) if billable_entity

      if billable_entity.save
        if billable_entity.is_a?(User)
          if plan_changed && billable_entity.is_a?(Organization) && plan_was == GitHub::Plan.business_plus
            billable_entity.disable_business_plus_features(actor: actor)
          end

          # The on_downgrade_to_free changes are normally executed after a user's Zuora subscription is cancelled, but
          # users that are disabled have already had their Zuora subscription cancelled since that is a part of the
          # disabling process. So for users that are disabled, we need to execute the on_downgrade_to_free changes here.
          if billable_entity.disabled? && plan_changed && (plan == GitHub::Plan.free || plan == GitHub::Plan.free_with_addons)
            billable_entity.on_downgrade_to_free
          end

          # remove any gated features if the user is on a free plan
          billable_entity.reload
          billable_entity.remove_gated_features
        end

        mark_complete
        log_success

        track_changes

        plan_trial = self.plan_trial
        if plan_trial.present? && plan_trial.enterprise_cloud?
          EnterpriseCloudTrial.new(user).deactivate!
        end

        true
      else
        log_failure
        billable_entity.errors.full_messages.each do |message|
          errors.add(:base, message)
        end

        false
      end
    end

    sig { returns(T::Boolean) }
    def enterprise_cloud_plan_trial_with_coupon?
      billable_entity = self.billable_entity
      !!(billable_entity.is_a?(Organization) && billable_entity.plan.business_plus? &&
        billable_entity.coupon&.present? && plan_trial&.enterprise_cloud?)
    end

    sig { returns(T.nilable(GitHub::Plan)) }
    def plan
      name = read_attribute(:plan)
      GitHub::Plan.find(name) if name.present?
    end

    sig { params(new_plan: T.nilable(T.any(GitHub::Plan, String, Symbol))).returns(T.nilable(T.any(GitHub::Plan, String, Symbol))) }
    def plan=(new_plan)
      write_attribute(:plan, new_plan.to_s)
    end

    sig { returns(T::Boolean) }
    def changing_plan?
      !!(plan? && billable_entity&.plan != plan)
    end

    sig { returns(T::Boolean) }
    def changing_seats?
      !!(seats.present? && billable_entity&.seats != seats)
    end

    sig { returns(T::Boolean) }
    def changing_duration?
      !!(plan_duration? && billable_entity&.plan_duration != plan_duration)
    end

    sig { returns(T::Boolean) }
    def changing_data_packs?
      !!(data_packs.present? && billable_entity&.data_packs != data_packs)
    end

    sig { returns(T::Boolean) }
    def has_changes?
      changing_plan? || changing_seats? || changing_duration? || changing_data_packs? || has_item_changes?
    end

    sig { returns(T::Boolean) }
    def has_item_changes?
      pending_subscription_item_changes.exists?
    end

    sig { returns(T::Boolean) }
    def incomplete?
      !is_complete?
    end

    # Public: Cancel a plan change so that it won't run as scheduled
    sig { returns(T::Boolean) }
    def cancel
      mark_complete
    end

    # Public: Cancels all pending subscription item changes so that they won't run as scheduled
    sig { void }
    def cancel_pending_subscription_item_changes!
      pending_subscription_item_changes.each { |item_change| item_change.destroy! }
    end

    private

    sig { returns(T.nilable(T::Boolean)) }
    attr_accessor :plan_changed

    sig { returns(T.nilable(GitHub::Plan)) }
    attr_accessor :plan_was

    sig { returns(T.nilable(T::Boolean)) }
    attr_accessor :seats_changed

    sig { returns(T.nilable(Integer)) }
    attr_accessor :seats_was

    sig { returns(T.nilable(T::Boolean)) }
    attr_accessor :plan_duration_changed

    sig { returns(T.nilable(String)) }
    attr_accessor :plan_duration_was

    sig { returns(T.nilable(String)) }
    attr_accessor :subscription_provider_was

    sig { returns(String) }
    def event_prefix
      "pending_plan_change"
    end

    sig { void }
    def instrument_creation
      return unless billable_entity = self.billable_entity
      payload = {
        active_on: active_on,
        actor: actor || billable_entity,
      }.tap do |p|
        p[billable_entity.event_prefix] = billable_entity
      end

      if changing_plan?
        payload[:plan_was] = billable_entity.plan.display_name
        payload[:plan] = T.must(plan).display_name
      end

      if changing_duration?
        payload[:plan_duration_was] = billable_entity.plan_duration
        payload[:plan_duration] = plan_duration.to_s
      end

      if changing_seats?
        payload[:seats_was] = billable_entity.seats.to_i
        payload[:seats] = seats
      end

      instrument :create, payload
    end

    sig { void }
    def instrument_updated
      payload = {
        active_on: active_on,
      }.tap do |p|
        p[billable_entity&.event_prefix] = billable_entity
      end
      if previous_changes[:plan].present?
        payload[:plan_was] = GitHub::Plan.find(previous_changes[:plan].first).try(:display_name)
        payload[:plan] = plan.try(:display_name)
      end

      if previous_changes[:plan_duration].present?
        payload[:plan_duration_was] = previous_changes[:plan_duration].try(:first)
        payload[:plan_duration] = plan_duration
      end

      if previous_changes[:seats].present?
        payload[:seats_was] = previous_changes[:seats].try(:first)
        payload[:seats] = seats
      end

      instrument :update, payload
    end

    sig { void }
    def instrument_run
      payload = {
        active_on: active_on,
      }.tap do |p|
        p[billable_entity&.event_prefix] = billable_entity
      end

      plan = self.plan

      payload[:plan] = plan.display_name if plan
      payload[:plan_duration] = plan_duration if plan_duration
      payload[:seats] = seats if seats

      instrument :run, payload
    end

    sig { void }
    def track_changes
      billable_entity = T.must(self.billable_entity)
      if billable_entity.is_a?(Business)
        business.instrument_change_billing_plan(
          business: business,
          plan: GitHub::Plan.business_plus.name.to_sym,
          old_plan: GitHub::Plan.business_plus.name.to_sym,
          old_plan_duration: plan_duration_was,
          plan_duration: plan_duration_changed ? plan_duration : plan_duration_was,
          old_seats: seats_was,
          seats: seats,
        )
        instrument_run
      else
        billable_entity.track_plan_change(actor, plan_was, old_seat_count: seats_was, old_subscription_provider: subscription_provider_was) if plan_changed
        billable_entity.track_seat_change(actor, old_seats: seats_was) if seats_changed
        if plan_duration_changed
          billable_entity.track_subscription_item_change_for_user_duration_change(T.must(actor), previous_plan_duration: plan_duration_was)
          billable_entity.track_plan_duration_change(actor, plan_duration_was.to_s)
        end
        instrument_run

        if seats_changed
          GlobalInstrumenter.instrument(
            "billing.seat_count_change",
            actor_id: actor&.id,
            user_id: user&.id,
            old_seat_count: seats_was,
            new_seat_count: seats,
          )
        end

        plan_trial = self.plan_trial
        if plan_trial.present?
          plan_trial.log_plan_change(new_plan: plan&.name, user_initiated: false)
        end
      end
    end

    sig { params(skip_sync: T::Boolean).void }
    def run_pending_subscription_item_changes(skip_sync: false)
      pending_subscription_item_changes.each do |change|
        change.run(skip_sync: true)
      end

      plan_subscriptions.each(&:synchronize_later) unless skip_sync
    end

    # Private: the Billing::PlanSubscription for this pending plan change.
    #
    # Billing::PendingSubscriptionItemChanges can be associated with a different Billing::PlanSubscription
    # depending on the subscription item's subscribable. This also includes the billable_entity's general plan subscription.
    sig { returns(T::Array[Billing::PlanSubscription]) }
    def plan_subscriptions
      pending_subscription_item_changes.map(&:plan_subscription).append(billable_entity&.plan_subscription).compact.uniq
    end

    sig { void }
    def log_failure
      if billable_business?
        Failbot.report runtime_error, { :app => "github-user", "gh.business.id" => business&.id }
      else
        Failbot.report runtime_error, { :app => "github-user", "gh.user.id" => user&.id }
      end

      log_data_dog_event(success: false) if attempts == 3
    end

    sig { void }
    def log_success
      log_data_dog_event(success: true)
    end

    sig { params(success: T::Boolean).void }
    def log_data_dog_event(success:)
      GitHub.dogstats.increment "account_management.pending_plan_change_run",
        tags: ["success:#{success}"]
    end

    sig { returns(RuntimeError) }
    def runtime_error
      entity = billable_business? ? "business" : "user"
      RuntimeError.new "Invalid Billing::PendingPlanChange state for #{entity}: #{error_message}"
    end

    sig { returns(String) }
    def error_message
      "#{billable_entity} - #{billable_entity&.errors.full_messages.to_sentence}"
    end

    sig { returns(T::Boolean) }
    def mark_complete
      update(is_complete: true, active_on: [GitHub::Billing.today, active_on].min)
    end
  end
end
