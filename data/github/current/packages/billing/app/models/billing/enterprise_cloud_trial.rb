# typed: true
# frozen_string_literal: true

module Billing
  class EnterpriseCloudTrial

    INITIAL_SEAT_COUNT = 50
    TRIAL_LENGTH = T.let(30.days, ActiveSupport::Duration)
    MAX_TRIAL_LENGTH = 90
    TOS_TYPE = "Evaluation"
    EXPIRATION_MESSAGE_DURATION = T.let(90.days, ActiveSupport::Duration)
    BANNER_LENGTH = T.let(7.days, ActiveSupport::Duration)

    include Instrumentation::Model
    include GitHub::BatchMethod

    delegate(:expired_within?, to: :plan_trial)
    delegate(:id, to: :plan_trial, prefix: true)

    def self.eligible?(org = nil)
      new(org).eligible?
    end

    def self.active?(org = nil)
      new(org).active?
    end

    sig { params(organization_ids: T.any(Integer, T::Array[Integer]), created_after: ActiveSupport::TimeWithZone).returns(T::Boolean) }
    def self.trial_exists_for?(organization_ids, created_after:)
      Billing::PlanTrial.where("created_at >= ?", created_after).for_plan(GitHub::Plan::BUSINESS_PLUS)
        .for_user(organization_ids).exists?
    end

    sig { returns(ActiveSupport::Duration) }
    def self.trial_length
      TRIAL_LENGTH
    end

    sig { params(organizations: T.any(ActiveRecord::Relation, T::Array[Organization])).returns(T::Array[Organization]) }
    def self.eligible_orgs_only(organizations)
      # Select orgs that are not on GHEC
      non_business_plus_orgs = organizations.reject { |org| org.business_plus? }
      # Get orgs ids that are have had a GHEC trial
      ineligible_org_ids = PlanTrial.for_user(non_business_plus_orgs.pluck(:id)).for_plan(GitHub::Plan::BUSINESS_PLUS)
        .pluck(:user_id)
      # Select only orgs that have not had a GHEC trial
      non_business_plus_orgs.reject { |org| ineligible_org_ids.include?(org.id) }
    end

    def initialize(organization)
      @organization = organization
    end

    sig { returns(T::Boolean) }
    def create
      return false unless eligible?
      return false unless (org = organization)

      Organization.transaction do
        old_plan = org.plan_name
        old_seats = org.seats

        # For team plan we do not want to change the seats count.
        # This is mainly because it gets tricky if the org is already billing for more than 50 seats.
        seats_for_trial = old_plan == GitHub::Plan::BUSINESS ? old_seats : INITIAL_SEAT_COUNT

        org.update!(
          plan: GitHub::Plan::BUSINESS_PLUS,
          seats: seats_for_trial,
        )

        pending_plan_change = org.pending_plan_changes.create!(
          plan: old_plan,
          active_on: GitHub::Billing.today + TRIAL_LENGTH,
          seats: old_seats,
        )

        Billing::PlanTrial.create(
          user: organization,
          pending_plan_change: pending_plan_change,
          plan: GitHub::Plan::BUSINESS_PLUS,
        )
        org.set_beta_features_for_plan

        log_signup(old_plan)

        Billing::EnterpriseCloudTrialCheckJob.perform_later(org.id)
        true
      end
    end

    sig { returns(T::Boolean) }
    def deactivate!
      update_terms
      pending_plan_change&.cancel.tap do
        log_trial_ended
      end
    end

    sig { returns(T::Boolean) }
    def eligible?
      return true if organization.nil?

      !PlanTrial.for_plan(GitHub::Plan::BUSINESS_PLUS).for_user(organization).exists?
    end

    sig { returns(T::Boolean) }
    def ever_been_in_trial?
      plan_trial.present?
    end

    sig { returns(Date) }
    def started_on
      plan_trial.created_at.in_time_zone(GitHub::Billing.timezone).to_date
    end

    sig { returns(Integer) }
    def days_active
      plan_trial_created_on = T.cast(plan_trial.created_at.in_time_zone(GitHub::Billing.timezone).to_date, Date)
      (GitHub::Billing.today - plan_trial_created_on).to_i
    end

    sig { returns(Integer) }
    def days_remaining
      return 0 if expired?
      return 0 unless (active_on = pending_plan_change&.active_on)

      T.unsafe(active_on - GitHub::Billing.today).to_i
    end

    sig { returns(T.any(Integer, Time)) }
    def time_remaining
      return 0 if pending_plan_change.nil?
      return 0 unless (active_on = pending_plan_change&.active_on)

      Time.at(active_on.to_time - GitHub::Billing.now)
    end

    sig { returns(Integer) }
    def duration_in_days
      return 0 if pending_plan_change.nil?
      return 0 unless (active_on = pending_plan_change&.active_on)

      T.unsafe(active_on - started_on).to_i
    end

    # Public: Check if the Enterprise Cloud trial is currently active.
    #
    # Examples
    #
    #   # To prevent N+1s when this method is called on a list of Billing::EnterpriseCloudTrial instances, prefill it
    #   # this way:
    #
    #   # Execute queries necessary to preload, such as in a controller action:
    #   GitHub::PrefillAssociations.prefill_batch_method(enterprise_cloud_trials, :active?)
    #
    #   enterprise_cloud_trials.each do |enterprise_cloud_trial|
    #     # Method is preloaded and memoized -- no queries are executed here!
    #     enterprise_cloud_trial.active?
    #   end
    #
    # Returns a Boolean.
    batch_method :active? do |enterprise_cloud_trials|
      GitHub::PrefillAssociations.prefill_batch_method(enterprise_cloud_trials, :plan_trial)

      plan_trials = enterprise_cloud_trials.map(&:plan_trial).compact
      GitHub::PrefillAssociations.prefill_associations(plan_trials, :pending_plan_change) # used in #active?

      enterprise_cloud_trials.each_with_object({}) do |enterprise_cloud_trial, hash|
        hash[enterprise_cloud_trial] = if enterprise_cloud_trial.organization_id.nil?
          false
        else
          !!enterprise_cloud_trial.plan_trial&.active?
        end
      end
    end

    sig { returns(T::Boolean) }
    def expired?
      !active?
    end

    sig { returns(String) }
    def description
      return "The trial expired #{days_remaining.abs} #{"day".pluralize(days_remaining.abs)} ago." if expired?
      "The trial has been active for #{days_active} #{"day".pluralize(days_active)} and has #{days_remaining} " \
        "#{"day".pluralize(days_remaining)} remaining."
    end

    sig { params(days: T.nilable(Integer)).returns(T::Boolean) }
    def can_extend_trial?(days = nil)
      return false unless (plan_change = pending_plan_change)

      if days.present?
        new_trial_end_date = T.unsafe(plan_change.active_on) + days
        plan_trial_created_on = plan_trial.created_at.in_time_zone(GitHub::Billing.timezone).to_date
        new_trial_length = (new_trial_end_date - plan_trial_created_on).to_i

        new_trial_length <= MAX_TRIAL_LENGTH
      else
        duration_in_days < MAX_TRIAL_LENGTH
      end
    end

    sig { params(days: Integer, ignore_max: T::Boolean).returns(T::Boolean) }
    def extend_trial(days, ignore_max: false)
      if ignore_max || can_extend_trial?(days)
        old_duration = duration_in_days

        T.must(pending_plan_change).update(
          is_complete: false,
          active_on: T.unsafe(T.must(pending_plan_change).active_on) + days,
        ).tap do
          log_trial_extension(old_duration: old_duration)
        end
      else
        false
      end
    end

    sig { returns(T.nilable(Date)) }
    def expires_on
      return unless ever_been_in_trial?

      pending_plan_change&.active_on
    end

    sig { params(new_plan: String, user_initiated: T::Boolean, active: T.nilable(T::Boolean)).void }
    def log_plan_change(new_plan:, user_initiated:, active: nil)
      plan_trial.log_plan_change(new_plan: new_plan, user_initiated: user_initiated, active: active)
    end

    # The time difference between a date time with the Plan Trial creation
    #
    # @param other [DateTime]
    #
    # @return [Float]
    sig { params(other: ActiveSupport::TimeWithZone).returns(Float) }
    def difference_between_plan_trial_creation(other)
      plan_trial.created_at - other
    end

    sig { params(user: User).returns(T::Boolean) }
    def should_display_banner_for?(user)
      return false if already_converted?
      return false unless ever_been_in_trial?
      return false unless T.must(organization).member?(user)
      # Only show banner for BANNER_LENGTH days after trial expiry
      return false if (T.unsafe(expires_on) + BANNER_LENGTH) <= GitHub::Billing.today
      # Do not show banner if trial ends early
      return false if expired? && (T.unsafe(started_on) + TRIAL_LENGTH) > GitHub::Billing.today

      true
    end

    sig { params(seats: Integer).returns(T.nilable(T::Boolean)) }
    def update_seat_change(seats)
      pending_plan_change&.update(seats: seats) if active? && !fallback_plan&.free?
    end

    sig { returns(T::Boolean) }
    def block_seat_change?
      active? || (fallback_plan.present? && T.must(fallback_plan).free?)
    end

    sig { returns(T.nilable(GitHub::Plan)) }
    def fallback_plan
      pending_plan_change&.plan
    end

    sig { returns(T.nilable(Integer)) }
    def fallback_seats
      T.must(pending_plan_change).seats
    end

    sig { returns(T.nilable(Integer)) }
    def organization_id
      organization&.id
    end

    # Public: Get the business-plus plan trial for this Enterprise Cloud trial's organization.
    #
    # Examples
    #
    #   # To prevent N+1s when this method is called on a list of Billing::EnterpriseCloudTrial instances, prefill it
    #   # this way:
    #
    #   # Execute queries necessary to preload, such as in a controller action:
    #   GitHub::PrefillAssociations.prefill_batch_method(enterprise_cloud_trials, :plan_trial)
    #
    #   enterprise_cloud_trials.each do |enterprise_cloud_trial|
    #     # Method is preloaded and memoized -- no queries are executed here!
    #     enterprise_cloud_trial.plan_trial
    #   end
    #
    # Returns a Billing::PlanTrial or nil.
    batch_method :plan_trial do |enterprise_cloud_trials|
      org_ids = enterprise_cloud_trials.map(&:organization_id).compact
      plan_trials_by_org_id = if org_ids.any?
        Billing::PlanTrial.for_plan(GitHub::Plan::BUSINESS_PLUS).for_user(org_ids).index_by(&:user_id)
      else
        {}
      end
      enterprise_cloud_trials.each_with_object({}) do |enterprise_cloud_trial, hash|
        hash[enterprise_cloud_trial] = plan_trials_by_org_id[enterprise_cloud_trial.organization_id]
      end
    end

    private

    attr_reader :organization

    sig { returns(T.nilable(Billing::PendingPlanChange)) }
    def pending_plan_change
      plan_trial&.pending_plan_change
    end

    sig { returns(T::Boolean) }
    def update_terms
      return false unless ever_been_in_trial?
      return false unless (org = organization)
      return false unless org.terms_of_service.evaluation?

      org.terms_of_service.update(
        type: "Corporate",
        actor: User.ghost,
        staff_actor: true,
        change_note: "auto update via enterprise cloud trial",
      )
    end

    sig { params(old_plan: String).void }
    def log_signup(old_plan)
      GlobalInstrumenter.instrument("trial.signup", {
        account: @organization,
        previous_plan: old_plan,
        current_plan: organization&.plan_name,
      })

      instrument(:trial_start)
    end

    sig { params(old_duration: Integer).void }
    def log_trial_extension(old_duration:)
      GlobalInstrumenter.instrument("trial.extended", {
        account: @organization,
        previous_duration_in_days: old_duration,
        new_duration_in_days: duration_in_days,
      })

      instrument(:trial_extend, {
        duration_in_days_was: old_duration,
        duration_in_days: duration_in_days,
      })
    end

    sig { void }
    def log_trial_ended
      instrument(:trial_end)
    end

    sig { returns(Symbol) }
    def event_prefix
      :billing
    end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def event_payload
      {
        org: @organization,
        plan: GitHub::Plan::BUSINESS_PLUS,
      }
    end

    sig { returns(T::Boolean) }
    def already_converted?
      expired? && organization&.business_plus?
    end
  end
end
