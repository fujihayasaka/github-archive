# typed: true
# frozen_string_literal: true

module Organization::ActionsMetricsDependency
  extend T::Helpers
  requires_ancestor { Organization }

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def actions_usage_metrics_enabled?(current_user)
    return false unless current_user
    return false unless proxima_or_dotcom? # dotcom or proxima (not GHES)
    return false unless GitHub.actions_enabled? && !actions_disabled? # make sure actions is turned on
    return false unless org_or_user_feature_enabled?(current_user, :actions_usage_metrics) # check feature on

    has_metrics_permissions?(current_user)
  end

  def has_insights_content_available_for?(viewer)
    return false unless insights_enabled?(viewer)
    return true if actions_usage_metrics_enabled?(viewer)
    return true if dependency_insights_visible?(viewer)
    api_insights_enabled?(viewer)
  end

  # returns true if dotcom and GHEC or if user can see metrics
  def insights_enabled?(current_user = nil)
    return not_ghes_and_biz_plus? unless current_user

    # If current_user is present, check if actions usage metrics are enabled
    not_ghes_and_biz_plus? || actions_usage_metrics_enabled?(current_user) # aum does not require biz_plus
  end

  # not GHES (single_tenant_enterprise) and business plus
  def not_ghes_and_biz_plus?
    !GitHub.single_tenant_enterprise? && business_plus?
  end

  private

  def proxima_or_dotcom?
    !GitHub.single_tenant_enterprise?
  end

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def employee_with_bypass?(current_user)
    return false unless current_user
    !!(current_user.employee? && current_user.feature_flag_enabled?(:actions_usage_metrics_owner_bypass, default: false))
  end

  # Return true if current user has permissions to see actions metrics
  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def has_metrics_permissions?(current_user)
    return false unless current_user
    adminable_by?(current_user) || can_read_organization_actions_usage_metrics?(current_user) || employee_with_bypass?(current_user)
  end

  def org_or_user_feature_enabled?(current_user, feature)
    return false unless current_user
    feature_flag_enabled?(feature, default: false) || current_user.feature_flag_enabled?(feature, default: false)
  end
end
