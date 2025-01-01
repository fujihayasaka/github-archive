# typed: strict
# frozen_string_literal: true

module Organization::CopilotMetricsDependency
  extend T::Helpers
  requires_ancestor { Organization }

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def copilot_metrics_enabled?(current_user)
    current_org = T.cast(self, Organization)

    return false unless current_user
    return false unless current_org.adminable_by?(current_user)

    copilot_org = copilot_organization(current_org)
    return false unless copilot_org.has_copilot_for_business? || copilot_org.has_trial?

    return true if copilot_feature_enabled?(current_org)
    return true if copilot_feature_enabled?(current_user)
    copilot_feature_enabled?(current_org.business)
  end

  private

  sig { params(entity: T.nilable(T.nilable(T.any(Organization, User, Business)))).returns(T::Boolean) }
  def copilot_feature_enabled?(entity)
    return false if entity.nil?
    entity.feature_enabled?(:copilot_metrics_onboarding_timeline_page)
  end

  sig { params(org: Organization).returns(Copilot::Organization) }
  def copilot_organization(org)
    ::Copilot::Organization.new(org)
  end
end
