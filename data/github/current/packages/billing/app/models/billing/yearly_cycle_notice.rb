# typed: true
# frozen_string_literal: true

module Billing
  class YearlyCycleNotice
    def self.run
      User.expiring_soon.yearly.paying.find_each do |user|
        has_yearly_plan = user.pending_cycle_plan_duration == User::BillingDependency::YEARLY_PLAN
        has_payment_amount = user.pending_cycle_payment_amount.dollars > 0
        if has_yearly_plan && has_payment_amount && !(user.plan.free? || user.plan.free_with_addons?)
          BillingNotificationsMailer.yearly_billing_notice(user).deliver_later
        end
      end
    end
  end
end
