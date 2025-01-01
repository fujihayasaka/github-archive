# typed: strict
# frozen_string_literal: true

module Organization::CopilotMetricsDependency
  extend T::Helpers
  requires_ancestor { Organization }

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def copilot_metrics_viewer_enabled?(current_user)
    check_metrics_access(current_user: current_user, feature_flag: :copilot_metrics_onboarding_timeline_page)
  end

  sig { params(current_user: T.nilable(User)).returns(T::Boolean) }
  def copilot_metrics_catalog_enabled?(current_user)
    check_metrics_access(current_user: current_user, feature_flag: :copilot_metrics_insights_navigator)
  end

  private

  sig { params(current_user: T.nilable(User), feature_flag: Symbol).returns(T::Boolean) }
  def check_metrics_access(current_user:, feature_flag:)
    T.bind(self, Organization)
    return false if current_user.nil?
    return false unless user_permitted_to_view?(current_user)
    return false unless org_has_copilot_access?

    return true if self.feature_enabled?(feature_flag)
    return true if current_user.feature_enabled?(feature_flag)
    !!self.business&.feature_enabled?(feature_flag)
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def user_permitted_to_view?(current_user)
    T.bind(self, Organization)

    if self.feature_enabled?(:copilot_metrics_ui_for_all_members) || current_user.feature_enabled?(:copilot_metrics_ui_for_all_members)
      self.member?(current_user)
    else
      self.adminable_by?(current_user)
    end
  end

  sig { returns(T::Boolean) }
  def org_has_copilot_access?
    T.bind(self, Organization)

    copilot_org = ::Copilot::Organization.new(self)
    copilot_org.has_copilot_for_business? || copilot_org.has_trial?
  end
end
