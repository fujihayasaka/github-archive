# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  module MaximumIdleTimeoutPolicy
    extend PolicyFilter
    extend PolicyOverrideStorage

    # Returns the applicable idle timeout in minutes for the codespaces by looking at:
    # org max idle timeout policies, user default idle timeout setting, and requested_idle_timeout_minutes
    def self.get_applicable_idle_timeout(user:, billable_owner:, repository:, requested_idle_timeout_minutes: nil, codespace_id: nil)
      user_idle_timeout_setting = user.codespace_default_idle_timeout

      # If the codespace isn't owned by an org or isn't in the flag, return the requested_idle_timeout_minutes, users setting or default
      unless idle_timeout_policy_enabled?(billable_owner)
        delete_has_override_key!(codespace_id)
        return return_default(requested_idle_timeout_minutes, user_idle_timeout_setting)
      end

      # Find lowest applicable org policy
      org_idle_timeout_maximum = get_maximums(
        billable_owner: billable_owner,
        repository: repository,
      ).min

      # If there are no policies, return the requested_idle_timeout_minutes, users setting or default
      if org_idle_timeout_maximum.nil?
        delete_has_override_key!(codespace_id)
        return return_default(requested_idle_timeout_minutes, user_idle_timeout_setting)
      end

      # Allow the requested_idle_timeout_minutes if it's within limits
      if within_policy_limits?(requested_idle_timeout_minutes, org_idle_timeout_maximum)
        delete_has_override_key!(codespace_id)
        return requested_idle_timeout_minutes
      end

      # Find lowest applicable idle timeout provided
      applicable_idle_timeout = [org_idle_timeout_maximum, user_idle_timeout_setting].compact.min

      has_override = applicable_idle_timeout == org_idle_timeout_maximum && org_idle_timeout_maximum != user_idle_timeout_setting
      toggle_has_override!(has_override, codespace_id)

      applicable_idle_timeout
    end

    def self.within_policy_limits?(requested, org_max)
      return false if requested.nil?
      requested.between?(Codespaces::PolicyConstraint::IDLE_TIMEOUT_MINIMUM_VALUE, org_max)
    end

    def self.return_default(requested_timeout, user_setting)
      requested_timeout || user_setting || Codespaces::VscsClient::AUTO_SHUTDOWN_MINUTES
    end

    def self.idle_timeout_policy_enabled?(billable_owner)
      billable_owner.organization?
    end

    def self.override_key(codespace_id)
      "has_max_idle_timeout_policy_override_#{codespace_id}"
    end

    def self.return_idle_timeout_notice?(billable_owner, codespace_id)
      idle_timeout_policy_enabled?(billable_owner) && has_override?(codespace_id)
    end

    def self.idle_timeout_notice(auto_shutdown_delay_minutes)
      return "" unless auto_shutdown_delay_minutes.present?

      "Idle timeout for this codespace is set to #{auto_shutdown_delay_minutes} minutes in compliance with your organization's policy"
    end

    sig { override.returns(String) }
    def self.policy_name
      Codespaces::PolicyConstraint::CODESPACES_ALLOWED_MAXIMUM_IDLE_TIMEOUT
    end
  end
end
