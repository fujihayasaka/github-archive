# typed: strict
# frozen_string_literal: true

module Billing
  class ChangeSubscription

    PlanType = T.type_alias { T.any(String, Symbol, GitHub::Plan) }
    # Public: Change subscription attributes for a subscription account.
    #
    # Must have an existing Customer record if updating the payment method.
    #
    # target          - A User or Organization changing their subscription
    # plan            - String of new plan name (optional)
    # actor           - User performing this action
    # plan_duration   - String duration either "month" or "year". (optional)
    #                   Defaults to existing plan duration
    # seats           - Integer number of seats for this plan. (optional)
    #                   Defaults to existing number of seats
    # job_status_id   - JobStatus ID to track the subscription change progress (optional)
    # payment_details - A Hash of payment details. (optional)
    #   :billing_extra    - String extra billing information.
    #   :paypal_nonce     - String nonce representing a paypal account (optional).
    #   :credit_card      - A Hash of potentially encrypted CC info, including:
    #     * :number           - CC number as a String.
    #     * :expiration_month - Expiration month as a String of form MM
    #     * :expiration_year  - Expiration year as a String of form YY
    #     * :cvv              - CVV as a String (e.g. "420")
    #   :billing_address  - The billing address as a Hash of optionally encrypted CC info
    #     * :country_name    - Country as a String
    #     * :region          - Region as a String
    #     * :postal_code     - Postal code as a String
    sig do
      params(
        target: User,
        actor: User,
        plan: T.nilable(PlanType),
        seats: T.nilable(Integer),
        seat_delta: T.nilable(Integer),
        plan_duration: T.nilable(String),
        payment_details: T.nilable(T::Hash[Symbol, T.untyped]),
        job_status_id: T.nilable(String)
      ).returns(GitHub::Billing::Result)
    end
    def self.perform(target, actor:, plan: nil, seats: nil, seat_delta: nil, plan_duration: nil, payment_details: nil, job_status_id: nil)
      new(target, actor: actor, plan: plan, seats: seats, seat_delta: seat_delta, plan_duration: plan_duration, payment_details: payment_details, job_status_id: job_status_id)
        .perform
    end

    # Public: Checks to see if the target can make the provided changes.
    sig do
      params(
        target: User,
        actor: User,
        plan: T.nilable(PlanType),
        seats: T.nilable(Integer),
        seat_delta: T.nilable(Integer),
        plan_duration: T.nilable(String),
        payment_details: T.nilable(T::Hash[Symbol, T.untyped]),
        job_status_id: T.nilable(String)
      ).returns(T::Boolean)
    end
    def self.can_perform?(target, actor:, plan: nil, seats: nil, seat_delta: nil, plan_duration: nil, payment_details: nil, job_status_id: nil)
      new(target, actor: actor, plan: plan, seats: seats, seat_delta: seat_delta, plan_duration: plan_duration, payment_details: payment_details, job_status_id: job_status_id)
        .can_perform?
    end

    sig { returns(User) }
    attr_accessor :target

    sig { returns(GitHub::Plan) }
    attr_accessor :plan

    sig { returns(User) }
    attr_accessor :actor

    sig { returns(String) }
    attr_accessor :plan_duration

    sig { returns(String) }
    attr_accessor :previous_plan_duration

    sig { returns(Integer) }
    attr_accessor :seats

    sig { returns(T.nilable(Integer)) }
    attr_accessor :seat_delta

    sig { returns(T::Hash[Symbol, T.untyped]) }
    attr_accessor :payment_details

    sig { returns(T.nilable(String)) }
    attr_accessor :job_status_id

    sig { returns(T.nilable(GitHub::Billing::Result)) }
    attr_accessor :result

    sig do
      params(
        target: User,
        actor: User,
        plan: T.nilable(PlanType),
        seats: T.nilable(Integer),
        seat_delta: T.nilable(Integer),
        plan_duration: T.nilable(String),
        payment_details: T.nilable(T::Hash[Symbol, T.untyped]),
        job_status_id: T.nilable(String)
      ).void
    end
    def initialize(target, actor:, plan: nil, seats: nil, seat_delta: nil, plan_duration: nil, payment_details: nil, job_status_id: nil)
      @target = target
      @actor = actor

      @plan = T.let(find_plan(plan || target.plan.try(:name)), GitHub::Plan)
      @seats = T.let(seats || (@plan.per_seat? ? target.seats : 0), Integer)
      @seat_delta = seat_delta
      @previous_plan_duration = T.let(target.plan_duration, String)
      @plan_duration = T.let(plan_duration || target.plan_duration, String)
      @payment_details = T.let(payment_details || {}, T::Hash[Symbol, T.untyped])
      @job_status_id = job_status_id
      @result = T.let(nil, T.nilable(::GitHub::Billing::Result))
    end

    sig { returns(GitHub::Billing::Result) }
    def perform
      if !target.valid?
        # Be bold if an invalid user gets passed in
        return GitHub::Billing::Result.failure target.errors.full_messages.join(", ")
      elsif !can_perform?
        return T.must(result)
      elsif changing_pricing_model?
        return change_pricing_model(job_status_id: job_status_id)
      elsif seat_delta && !can_change_seat_amount?
        return T.must(result)
      end

      return downgrade_plan if is_downgrade?

      disabled_due_to_payment_method_issue = target.disabled? && target.should_disable?(check_plan_limit: false)
      validation_result = target.validate_purchases_allowed(actor: actor, check_disabled: disabled_due_to_payment_method_issue)
      return validation_result if validation_result.failed?

      feature_type = seat_delta ? :noncommercial : :default
      if target.needs_valid_payment_method_to_switch_to_plan?(plan, seats, feature_type:) && !has_payment_details?
        return GitHub::Billing::Result.failure "A credit card or other payment method is required to upgrade to that plan."
      elsif has_payment_details?
        result = create_or_update_payment_method
        return result if result.failed?
      end

      target.seats = seats
      target.plan_duration = plan_duration
      target.plan = plan

      # We need to update the pending plan change with any changes to the target's subscription
      if pending_cycle_change = target.pending_cycle_change
        pending_cycle_change.seats = seats if seats
        pending_cycle_change.plan_duration = plan_duration if plan_duration
        pending_cycle_change.plan = plan if target.plan_changed?
        pending_cycle_change.save
      end

      self.plan_changed = target.plan_changed?
      self.plan_was = target.plan_was

      self.seats_changed = target.seats_changed?
      self.seats_was = target.seats_was

      if target.apple_iap_subscription?
        self.subscription_provider_was = Billing::PlanSubscription::APPLE_IAP
      end

      # Skip the automatic external subscription update - for synchronous payments, the first
      # synchronization after the plan change must be run from CollectPaymentOnUpgradeJob.
      target.skip_update_external_subscription = true
      target.save

      track_subscription_sync(target)

      # create external subscription if changing plans from Free
      unless target.external_subscription?
        GitHub::Billing.transition_to_external_subscription(target, skip_sync: true)
      end

      # Start a job to synchronize and collect payment for the plan or seat change
      if target.collect_payment_immediately_for_plan_or_seat_changes?
        Billing::JobStatus.find(job_status_id)&.queued!
        CollectPaymentForUpgradeJob.perform_later(
          billable_entity: target,
          old_plan_name: self.plan_was&.name || "free",
          old_seat_count: self.seats_was.to_i,
          job_status_id: job_status_id,
          actor: actor,
        )
      else
        target.plan_subscription&.synchronize_later
      end

      track_changes

      GitHub::Billing::Result.success
    end

    # Public: Checks to see if the user can change to a particular plan by an actor.
    #         If no actor is defined, it assumes the user itself.
    sig { returns(T::Boolean) }
    def can_perform?
      return can_change_to_pro?        if plan.pro?
      return can_change_to_business?   if plan.business? || plan.business_plus?
      return can_change_to_repository? if plan.per_repository?
      return can_change_to_free?       if free_plan?
      true
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

    sig { returns(T.nilable(String)) }
    attr_accessor :subscription_provider_was

    sig { params(target: User).void }
    def track_subscription_sync(target)
      Billing::SubscriptionSyncStatus.retry_on_find_or_create_error do
        subscription_sync_status = Billing::SubscriptionSyncStatus.find_by(target: target) ||
          Billing::SubscriptionSyncStatus.new(target: target)
        subscription_sync_status.external_sync_status = :pending
        subscription_sync_status.save
      end
    end

    sig { returns(T::Boolean) }
    def can_change_to_pro?
      if target.user? && !target.plan.pro? || can_change_plan_duration?
        true
      elsif target.user? && target.plan == plan
        set_failure!("Already on the Personal plan.")
        false
      else
        set_failure!("Cannot move to a Personal plan.")
        false
      end
    end

    sig { returns(T::Boolean) }
    def can_change_to_business?
      if target.organization? && (!target.invoiced? || actor.site_admin? || can_change_plan_duration?)
        true
      else
        set_failure!("Please contact support if you want to migrate to the per-seat pricing plan.")
        false
      end
    end

    sig { returns(T::Boolean) }
    def can_change_to_repository?
      upgrade_restriction = Billing::PlanChange::LegacyUpgradeRestriction.new(target: target, actor: actor)
      already_per_repo = target.plan.per_repository?
      # NB: github staff are allowed to move orgs to per_repo plans
      #     that the org's admins wouldn't normally have access to
      staff_admining_an_org = actor.site_admin? && target.organization?

      if !staff_admining_an_org && (!already_per_repo || !upgrade_restriction.allow_plan?(plan))
        verb = already_per_repo ? "upgrade" : "move to"
        set_failure!("Cannot #{verb} a per-repository plan.")
        false
      elsif target.owned_private_repositories.size > plan.limit(:repos, visibility: :private)
        set_failure!("Too many repositories to change to the #{plan.name.capitalize} plan.")
        false
      else
        true
      end
    end

    sig { returns(T::Boolean) }
    def can_change_plan_duration?
      changing_plan_duration? &&
        ((plan == target.plan) ||
         (plan.per_repository? == target.plan.per_repository?))
    end

    sig { returns(T::Boolean) }
    def can_change_to_free?
      if target.invoiced? && !actor.site_admin?
        set_failure!("Your account is being invoiced. Please contact support to make plan changes.")
        return false
      elsif target.over_repo_seat_limit? && !actor.site_admin?
        set_failure!("Your account can not be downgraded yet because one or more of your private repositories is over the collaborator limit for the free plan. Please make sure that each of the private repositories owned by your account (#{target.login}) below has #{GitHub::Plan.free.limit(:collaborators, visibility: :private)} or fewer collaborators before downgrading your account. Questions?")
        return false
      end
      true
    end

    MAX_SEAT_DELTA = 300

    sig { returns(T::Boolean) }
    def can_change_seat_amount?
      seat_delta = self.seat_delta.to_i

      if seat_delta == 0
        set_failure!("You must add or remove at least 1 seat.")
        false
      elsif !seat_delta.between?(MAX_SEAT_DELTA * -1, MAX_SEAT_DELTA)
        set_failure!("You can only add or remove up to #{MAX_SEAT_DELTA} seats at a time.")
        false
      else
        true
      end
    end

    # Private: Returns whether the plan duration is being changed.
    sig { returns(T::Boolean) }
    def changing_plan_duration?
      plan_duration != previous_plan_duration
    end

    # Private: Sets the error result with the given message.
    sig { params(msg: String).void }
    def set_failure!(msg)
      @result = GitHub::Billing::Result.failure msg
    end

    # Private: Track changes in the horribly named Transactions table and
    #          the Audit Log.
    sig { void }
    def track_changes
      if plan_changed
        target.track_plan_change(actor, plan_was, old_subscription_provider: subscription_provider_was)
      end

      if seats_changed
        target.track_seat_change(actor, old_seats: seats_was)
      end
    end

    # Private: Enables or disables the account and individual repos, as applicable
    sig { void }
    def enable_or_disable_account
      target.enable_or_disable!
    end

    sig { returns(GitHub::Billing::Result) }
    def create_or_update_payment_method
      if target.has_billing_record?
        GitHub::Billing.update_payment_method(target, payment_details, skip_synchronization: true)
      else
        GitHub::Billing.create_customer(target, payment_details, actor: actor)
      end
    end

    sig { returns(T::Boolean) }
    def has_payment_details?
      Billing::PaymentDetails.new(payment_details).valid?
    end

    sig { params(plan: T.any(String, Symbol, GitHub::Plan)).returns(GitHub::Plan) }
    def find_plan(plan)
      new_plan = GitHub::Plan.find!(plan)

      if (target.data_packs > 0 || target.subscription_items.any?) && new_plan.free?
        GitHub::Plan.find!("free_with_addons")
      else
        new_plan
      end
    end

    sig { returns(T::Boolean) }
    def changing_pricing_model?
      !free_plan? && (target.plan.per_seat? ^ plan.per_seat?)
    end

    sig { params(job_status_id: T.nilable(String)).returns(GitHub::Billing::Result) }
    def change_pricing_model(job_status_id: nil)
      pricing_model = Billing::PlanChange::PerSeatPricingModel.new(target, new_plan: plan)
      success = pricing_model.switch(actor: actor, job_status_id: job_status_id)
      enable_or_disable_account
      GitHub::Billing::Result.new(success)
    end

    sig { returns(T::Boolean) }
    def is_downgrade?
      return false if target.invoiced?
      downgrading_seats? || delayed_duration_change? || downgrading_plan?
    end

    sig { returns(GitHub::Billing::Result) }
    def downgrade_plan
      Billing::SchedulePlanChange.run(
        account: target,
        actor: actor,
        seats: seats,
        plan: plan,
        plan_duration: plan_duration,
        active_on: target.github_plan_next_billing_date,
      ).tap do |result|
        update_current_enterprise_cloud_trial_seat_change if result.success? && downgrading_seats?
      end
    end

    sig { void }
    def update_current_enterprise_cloud_trial_seat_change
      Billing::EnterpriseCloudTrial.new(target).update_seat_change(seats)
    end

    sig { returns(T::Boolean) }
    def delayed_duration_change?
      changing_plan_duration? && target.payment_amount > 0
    end

    sig { returns(T::Boolean) }
    def downgrading_seats?
      !!(plan.per_seat? && target.seats > seats)
    end

    sig { returns(T::Boolean) }
    def downgrading_plan?
      changing_plan? && target.undiscounted_payment_difference(plan, seat_count: seats) < 0
    end

    sig { returns(T::Boolean) }
    def changing_plan?
      target.plan != plan
    end

    sig { returns(T::Boolean) }
    def free_plan?
      plan.free? || plan.free_with_addons?
    end
  end
end
