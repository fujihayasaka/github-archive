# typed: true
# frozen_string_literal: true

module CopilotSpaces
  module Enabled
    extend T::Helpers

    # Copilot Spaces can be opted out per enterprise via a feature flag,
    # then enabled for specific users via another feature flag.
    sig { params(user: T.nilable(User)).returns(T::Boolean) }
    def self.copilot_spaces_enabled_for_user?(user)
      return false if user.nil?

      # Check if user is specifically blocked from Copilot Spaces
      return false if FeatureFlag.vexi.enabled?(:copilot_spaces_user_blocked, user, default: false)

      businesses = user.businesses.to_a # vexi wants an array here
      allowed_by_flag = !FeatureFlag.vexi.enabled?(:copilot_spaces_enterprise_opt_out, businesses, default: false) ||
      FeatureFlag.vexi.enabled?(:copilot_spaces_enterprise_user_opt_in, user, default: false)

      # Be sure to include CopilotPublicUserCacheable in test classes
      # that exercise this method, or Copilot::Public::User.for(user).has_copilot_access?
      # will fail.
      copilot_public_user = Copilot::Public::User.for(user)
      has_copilot_access = copilot_public_user.has_copilot_access?
      return false unless allowed_by_flag && has_copilot_access

      # Check the spaces policy if the feature flag is enabled
      if user.feature_flag_enabled?(:copilot_spaces_policy_ga, default: false)
        copilot_user = Copilot::User.new(user)
        Copilot::Policies::Spaces.effective_value(copilot_user) == "enabled"
      else
        # If policy is not enabled, fall back to the existing flag-based logic. If we've made it
        # this far, the user has copilot access and is allowed by flag.
        true
      end
    end
  end
end
