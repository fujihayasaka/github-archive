# typed: strict
# frozen_string_literal: true

module Organization::DependencyInsightsDependency
  extend T::Helpers
  requires_ancestor { Organization }

  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def dependency_insights_enabled_for?(viewer)
    return false unless GitHub.dependency_graph_enabled?
    return false unless business_plus?

    if members_can_view_dependency_insights?
      member?(viewer) || adminable_by?(viewer)
    else
      adminable_by?(viewer)
    end
  end

  # Used by the organization insights tab
  sig { params(viewer: T.nilable(User)).returns(T::Boolean) }
  def dependency_insights_visible?(viewer)
    return false if GitHub.single_or_multi_tenant_enterprise?
    dependency_insights_enabled_for?(viewer)
  end
end
