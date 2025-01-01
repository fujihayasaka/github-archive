# typed: strict
# frozen_string_literal: true

module Organization::CopilotMetricsDependency
  extend T::Helpers
  include GitHub::Memoizer
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
    return false unless insights_policy_enabled?(current_user)

    return true if self.feature_flag_enabled?(feature_flag, default: false)
    return true if current_user.feature_flag_enabled?(feature_flag, default: false)
    !!self.business&.feature_flag_enabled?(feature_flag, default: false)
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def user_permitted_to_view?(current_user)
    T.bind(self, Organization)

    if self.feature_flag_enabled?(:copilot_metrics_ui_for_all_members, default: false) || current_user.feature_flag_enabled?(:copilot_metrics_ui_for_all_members, default: false)
      self.member?(current_user)
    else
      self.adminable_by?(current_user)
    end
  end

  sig { returns(T::Boolean) }
  def org_has_copilot_access?
    T.bind(self, Organization)

    copilot_organization.has_copilot_for_business? || copilot_organization.has_trial?
  end

  sig { params(current_user: User).returns(T::Boolean) }
  def insights_policy_enabled?(current_user)
    T.bind(self, Organization)

    if FeatureFlag.vexi.enabled?(:enforce_copilot_insights_policy, self, default: false) ||
      FeatureFlag.vexi.enabled?(:enforce_copilot_insights_policy, self.business, default: false) ||
      FeatureFlag.vexi.enabled?(:enforce_copilot_insights_policy, current_user, default: false)
      copilot_organization.insights_enabled?
    else
      true
    end
  end

  sig { returns(::Copilot::Organization) }
  memoize def copilot_organization
    T.bind(self, Organization)

    ::Copilot::Organization.new(self)
  end
end
