# typed: true
# frozen_string_literal: true

class Orgs::CopilotSettings::BaseController < Orgs::Controller
  include ApplicationHelper

  before_action :dotcom_required
  before_action :org_admins_only

  private

  sig { returns(Copilot::Organization) }
  memoize def copilot_organization
    T.must_because(current_copilot_organization) { "#org_admins_only ensures non-nil" }
  end

  sig { void }
  def check_not_legacy_plan
    render_404 if current_organization.plan.legacy?
  end

  sig { void }
  def check_copilot_available
    render_404 unless copilot_organization.has_copilot_for_business? || (copilot_organization.business_trial && T.must(copilot_organization.business_trial).has_trial?)
  end

  sig { void }
  def check_copilot_ga_available
    render_404 unless current_user&.feature_flag_enabled?(:copilot_custom_models_ga, default: false) || current_organization.feature_flag_enabled?(:copilot_custom_models_ga, default: false)
  end

  sig { returns(T::Boolean) }
  def code_review_approval_settings_enabled?
    code_review_approval_setting_enabled_for_current_rollout? || code_review_qualified_approval_setting_enabled_for_current_rollout?
  end

  sig { params(setting_type: T.nilable(Symbol)).returns(T::Boolean) }
  def code_review_approval_setting_type_enabled_for_current_rollout?(setting_type)
    case setting_type
    when :approval
      code_review_approval_setting_enabled_for_current_rollout?
    when :qualified_approval
      code_review_qualified_approval_setting_enabled_for_current_rollout?
    else
      false
    end
  end

  sig { returns(T::Boolean) }
  def code_review_approval_setting_enabled_for_current_rollout?
    current_organization.feature_flag_enabled?(:ccr_auto_approve_reviews, default: false)
  end

  sig { returns(T::Boolean) }
  def code_review_qualified_approval_setting_enabled_for_current_rollout?
    current_organization.feature_flag_enabled?(:ccr_copilot_qualified_approvals, default: false)
  end
end
