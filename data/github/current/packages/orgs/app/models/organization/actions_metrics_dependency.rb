# typed: true
# frozen_string_literal: true

module Organization::ActionsMetricsDependency
  extend T::Helpers
  requires_ancestor { Organization }

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def actions_usage_metrics_enabled?(current_user)
    return false unless current_user
    return false if GitHub.single_or_multi_tenant_enterprise?
    actions_metrics_enabled?(current_user, :actions_usage_metrics)
  end

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def actions_performance_metrics_enabled?(current_user)
    return false unless current_user
    return false if GitHub.single_or_multi_tenant_enterprise?
    actions_metrics_enabled?(current_user, :actions_performance_metrics)
  end

  def has_insights_content_available_for?(viewer)
    return false unless insights_enabled?
    return true if actions_usage_metrics_enabled?(viewer)
    return true if actions_performance_metrics_enabled?(viewer)
    return true if dependency_insights_visible?(viewer)
    api_insights_enabled?(viewer)
  end

  # returns true if dotcom and GHEC or if dotcom and user can see metrics
  def insights_enabled?(current_user = nil)
    if current_user != nil
      return insights_dotcom_and_business_plus? || (dotcom? && feature_enabled?(:actions_usage_metrics_all_orgs) && has_metrics_permissions?(current_user))
    end

    insights_dotcom_and_business_plus? || (dotcom? && feature_enabled?(:actions_usage_metrics_all_orgs) && metrics_enabled?)
  end

  def insights_dotcom_and_business_plus?
    !GitHub.single_tenant_enterprise? && business_plus?
  end

  private

  def dotcom?
    !GitHub.single_or_multi_tenant_enterprise?
  end

  # Return true if actions metrics can be turned on in this environment
  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def metrics_possible?(current_user)
    return false unless current_user
    insights_dotcom_and_business_plus? || (dotcom? && org_or_user_feature_enabled?(current_user, :actions_usage_metrics_all_orgs))
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
    adminable_by?(current_user) || can_read_organization_actions_usage_metrics?(current_user) || employee_with_bypass?(current_user)
  end

  def metrics_enabled?
    # this is safe to do because AUM is in GA, but we should clean up the AUM FF soon and then this would always return true
    feature_enabled?(:actions_usage_metrics) || feature_enabled?(:actions_performance_metrics)
  end

  def actions_metrics_enabled?(current_user, feature)
    return false unless GitHub.actions_enabled? && !actions_disabled? # make sure actions is turned on
    return false unless org_or_user_feature_enabled?(current_user, feature) # check usage or performance feature on

    has_metrics_permissions?(current_user) && metrics_possible?(current_user) # has permissions and metrics works in this env
  end

  def org_or_user_feature_enabled?(current_user, feature)
    return false unless current_user
    feature_enabled?(feature) || current_user.feature_enabled?(feature)
  end
end
