# typed: strict
# frozen_string_literal: true

module Organization::ApiInsightsDependency
  extend T::Helpers
  extend T::Sig
  requires_ancestor { Organization }

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def api_insights_enabled?(current_user)
    return false unless current_user
    return false unless !GitHub.single_or_multi_tenant_enterprise? && business_plus?
    return false unless current_user.feature_enabled?(:api_insights)
    can_view_org_api_insights?(current_user)
  end
end
