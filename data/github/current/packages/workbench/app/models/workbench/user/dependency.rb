# typed: true
# frozen_string_literal: true

module Workbench::User::Dependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { User }

  sig { returns(T::Boolean) }
  def spark_workbench_preview_enabled?
    T.bind(self, ::User)

    if self.feature_enabled?(:workbench_enable_enterprise_access_policy)
      # If user is not a member of any organization or enterprise, they have Spark access
      # based on the normal feature flag setting.
      return self.feature_enabled?(:copilot_workbench) if !self.is_enterprise_managed? && self.organizations.count == 0

      # If the user is enterprise managed, we need to check if the enterprise has disabled Spark
      if self.is_enterprise_managed?
        copilot_business = Copilot::Business.new(enterprise_managed_business)
        return false if copilot_business.copilot_disabled?
        return false if copilot_business.beta_features_github_chat_disabled?
      end

      copilot_user = Copilot::User.new(self)

      # Return true if any organization giving the user a Copilot license has both Copilot for dotcom enabled and
      # preview features enabled
      return true if copilot_user.copilot_organizations.any? do |org|
        org.copilot_for_dotcom_enabled? && org.beta_features_github_chat_enabled?
      end

      return false
    end

    # If user has the developer Spark FF enabled, they have access
    self.feature_enabled?(:copilot_workbench)
  end
end
