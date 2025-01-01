# typed: true
# frozen_string_literal: true

require "github/billing"

module Business::ActionsMetricsDependency
  extend T::Helpers
  requires_ancestor { Business }

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def actions_usage_metrics_enabled?(current_user)
    return false unless current_user
    return false unless proxima_or_dotcom? # dotcom or proxima (not GHES)
    return false unless GitHub.actions_enabled? && !actions_disabled? # make sure actions is turned on
    return false unless enterprise_or_user_feature_enabled?(current_user, :actions_usage_metrics) # check feature on for actions metrics
    return false unless enterprise_or_user_feature_enabled?(current_user, :actions_usage_metrics_enterprise) # check feature on for enterprise page

    has_metrics_permissions?(current_user)
  end

  def insights_enabled?(current_user = nil)
    return false unless current_user
    actions_usage_metrics_enabled?(current_user)
  end

  private

  def proxima_or_dotcom?
    !GitHub.single_tenant_enterprise?
  end

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def employee_with_bypass?(current_user)
    return false unless current_user
    !!(current_user.employee? && current_user.feature_enabled?(:actions_usage_metrics_owner_bypass))
  end

  # Return true if current user has permissions to see actions metrics
  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def has_metrics_permissions?(current_user)
    return false unless current_user
    owner?(current_user) || employee_with_bypass?(current_user)
  end

  def enterprise_or_user_feature_enabled?(current_user, feature)
    return false unless current_user
    feature_enabled?(feature) || current_user.feature_enabled?(feature)
  end
end
