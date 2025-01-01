# typed: true
# frozen_string_literal: true

module Organization::ActionsMetricsDependency
  extend T::Helpers
  extend T::Sig
  requires_ancestor { Organization }

  sig { params(current_user: User).returns(T::Boolean) }
  def actions_usage_metrics_enabled?(current_user)
    return false unless GitHub.actions_enabled? && !actions_disabled?
    return false unless feature_enabled?(:actions_usage_metrics) || current_user.feature_enabled?(:actions_usage_metrics)
    # Important: Keep this check even after FF is removed! Only admins or aum readers should currently have access to AUM.
    ((adminable_by?(current_user) || can_read_organization_actions_usage_metrics?(current_user)) && insights_enabled?) || employee_with_bypass?(current_user)
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def actions_performance_metrics_enabled?(current_user)
    return false unless GitHub.actions_enabled? && !actions_disabled?
    return false unless feature_enabled?(:actions_performance_metrics) || current_user.feature_enabled?(:actions_performance_metrics)
    # Important: Keep this check even after FF is removed! Only admins or aum readers should currently have access to AUM.
    ((adminable_by?(current_user) || can_read_organization_actions_usage_metrics?(current_user)) && insights_enabled?) || employee_with_bypass?(current_user)
  end

  def has_insights_content_available_for?(viewer)
    return false unless insights_enabled?

    dependency_insights_enabled_for?(viewer) || actions_usage_metrics_enabled?(viewer) || api_insights_enabled?(viewer)
  end

  # Check whether the Insights feature is enabled.  The feature is only available
  # for orgs with a business_plus billing plan in dotcom
  #
  # If you're looking at this code, you might be wondering: Where is this supported?
  #  The answer is: dotcom only. Org level insights is not enabled in GHES.
  #
  # Returns a Boolean value.
  def insights_enabled?
    !GitHub.single_or_multi_tenant_enterprise? && business_plus?
  end

  private

  sig { params(current_user: User).returns(T::Boolean) }
  def employee_with_bypass?(current_user)
    !!(current_user.employee? && current_user.feature_enabled?(:actions_usage_metrics_owner_bypass))
  end
end
