# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module MaximumRetentionPeriodPolicy
    extend T::Sig
    extend PolicyFilter
    extend PolicyOverrideStorage

    # Returns the applicable retention period in minutes for the codespaces by looking at:
    # org max retention period policies, user default retention period setting, and requested_retention_period_minutes
    def self.get_applicable_retention_period(user:, billable_owner:, repository:, requested_retention_period_minutes: nil, codespace_id: nil)
      user_retention_period_setting = user.codespace_default_retention_period

      # If the codespace isn't owned by an org or isn't in the flag, return the requested_retention_period_minutes, users setting or default
      unless retention_period_policy_enabled?(billable_owner)
        delete_has_override_key!(codespace_id)

        return return_default(requested_retention_period_minutes, user_retention_period_setting, billable_owner)
      end

      # Find lowest applicable org policy
      org_retention_period_maximum = get_maximums(
        billable_owner: billable_owner,
        repository: repository
      ).min

      # If there are no policies, return the requested_retention_period_minutes, users setting or default
      if org_retention_period_maximum.nil?
        delete_has_override_key!(codespace_id)

        return return_default(requested_retention_period_minutes, user_retention_period_setting, billable_owner)
      end

      # Allow the requested_retention_period_minutes if it's within limits
      if within_policy_limits?(requested_retention_period_minutes, org_retention_period_maximum)
        delete_has_override_key!(codespace_id)

        return requested_retention_period_minutes
      end

      # Find lowest applicable retention period provided
      applicable_retention_period = [org_retention_period_maximum, user_retention_period_setting].compact.min
      has_override = applicable_retention_period == org_retention_period_maximum && org_retention_period_maximum != user_retention_period_setting
      toggle_has_override!(has_override, codespace_id)

      applicable_retention_period
    end

    def self.exists?(billable_owner:, repository:)
      get_maximums(billable_owner: billable_owner, repository: repository).present?
    end

    def self.within_policy_limits?(requested, org_max)
      return false if requested.nil?
      requested.between?(Codespaces::PolicyConstraint::RETENTION_PERIOD_MINIMUM_VALUE, org_max)
    end

    def self.return_default(requested_period, user_setting, billable_owner)
      retention_period = requested_period || user_setting

      retention_period || Codespace::MAX_RETENTION_PERIOD
    end

    def self.retention_period_policy_enabled?(billable_owner)
      billable_owner.organization?
    end

    def self.return_retention_period_notice?(billable_owner, codespace_id)
      retention_period_policy_enabled?(billable_owner) && has_override?(codespace_id)
    end

    def self.override_key(codespace_id)
      "has_max_retention_period_policy_override_#{codespace_id}"
    end

    def self.retention_period_notice(retention_period_minutes)
      return "" unless retention_period_minutes.present?

      if retention_period_minutes >= 1440
        days = retention_period_minutes.minutes.in_days.to_i
        "Retention period for this codespace is set to #{days} #{'day'.pluralize(days)} in compliance with your organization's policy"
      else
        "Retention period for this codespace is set to #{retention_period_minutes} #{'minute'.pluralize(retention_period_minutes)} in compliance with your organization's policy"
      end
    end

    sig { override.returns(String) }
    def self.policy_name
      Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_RETENTION_PERIOD
    end
  end
end
