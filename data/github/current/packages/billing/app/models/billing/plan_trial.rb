# typed: strict
# frozen_string_literal: true

module Billing
  # PlanTrial links a pending plan change to a GitHub Plan in to keep track of users
  # who have signed up for the trial.
  class PlanTrial < ApplicationRecord::Domain::Billing

    belongs_to :user, inverse_of: :plan_trials
    belongs_to :pending_plan_change

    scope :for_user, ->(user_or_id) { where(user_id: user_or_id) }
    scope :for_plan, ->(plan_name) { where(plan: plan_name) }

    sig { returns(T::Boolean) }
    def active?
      change = self.pending_plan_change
      !!(change.present? && !change.is_complete?)
    end

    sig { params(days: T.any(Integer, ActiveSupport::Duration)).returns(T::Boolean) }
    def expired_within?(days)
      expires_on = self.expires_on
      !!(
        !active? &&
        expires_on.present? &&
        expires_on > GitHub::Billing.today - days
      )
    end

    sig { params(new_plan: T.any(GitHub::Plan, String), user_initiated: T::Boolean, active: T::Boolean).void }
    def log_plan_change(new_plan:, user_initiated:, active: active?)
      GlobalInstrumenter.instrument(
        "trial.plan_change",
        account: user,
        trial_plan: plan,
        new_plan: new_plan,
        trial_expired: !active,
        user_initiated: user_initiated,
      )
    end

    sig { returns(T::Boolean) }
    def enterprise_cloud?
      plan == GitHub::Plan::BUSINESS_PLUS
    end

    private

    sig { returns(T.nilable(Date)) }
    def expires_on
      pending_plan_change&.active_on
    end
  end
end
