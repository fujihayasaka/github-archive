# typed: true
# frozen_string_literal: true

require "github/transitions/20230313195345_advanced_security_monthly_trial_does_not_bill_on_expiration"

class AdvancedSecurityMonthlyTrialDoesNotBillOnExpirationTransition < ActiveRecord::Migration[7.1]
  def self.up
    return if !GitHub.enterprise? && !Rails.env.development?
    transition = GitHub::Transitions::AdvancedSecurityMonthlyTrialDoesNotBillOnExpiration.new(dry_run: false)
    transition.perform
  end

  def self.down
  end
end
