# typed: strict
# frozen_string_literal: true

module Organization::ApiInsightsDependency
  extend T::Helpers
  requires_ancestor { Organization }

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def api_insights_enabled?(current_user)
    return false unless current_user
    return false unless !GitHub.single_tenant_enterprise? && business_plus?
    return false unless self.feature_enabled?(:api_insights) || current_user.feature_enabled?(:api_insights)
    return true if can_view_org_api_insights?(current_user)
    # temporary bypass for employees working on api insights
    return false unless current_user.employee?
    current_user.feature_enabled?(:api_insights_owner_bypass)
  end
end
