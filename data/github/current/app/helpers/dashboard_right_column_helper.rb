# typed: true
# frozen_string_literal: true

module DashboardRightColumnHelper
  def onboarding_promos(context)
    current_user = context[:current_user]
    current_copilot_user_v2 = context[:current_copilot_user_v2]
    [
      {
        feature: :dashboard_onboarding_copilot_free_nudge,
        notice: :dashboard_onboarding_copilot_free,
        partial: "dashboard/promos/copilot_free",
        extra_condition: -> {
          return false if !current_user.feature_enabled?(:dashboard_onboarding_copilot_free_nudge)
          return false if GitHub.multi_tenant_enterprise? || current_user.is_enterprise_managed? || GitHub.enterprise?
          return false unless current_user.subscribed_to_in_product_messages?
          return true if current_copilot_user_v2.nil?
          true unless (
            current_copilot_user_v2.has_limited_access? ||
            current_copilot_user_v2.has_trial_access? ||
            current_copilot_user_v2.has_paid_ci_access? ||
            current_copilot_user_v2.has_free_pro_access? ||
            current_copilot_user_v2.has_cb_access? ||
            current_copilot_user_v2.has_ce_access?
          )
        }
      },
    ]
  end

  def marketing_promos(context)
    current_user = context[:current_user]
    current_copilot_user_v2 = context[:current_copilot_user_v2]
    request = context[:request]
    [
      {
        feature: :dashboard_copilot_agent_mode_launch_nudge,
        notice: :dashboard_copilot_agent_mode_launch_nudge,
        partial: "dashboard/promos/copilot_agent_mode_launch",
        extra_condition: -> {
          return false if !current_user.feature_enabled?(:dashboard_copilot_agent_mode_launch_nudge)
          return false if GitHub.multi_tenant_enterprise? || current_user&.is_enterprise_managed? || GitHub.enterprise?
          return false unless current_user.subscribed_to_in_product_messages?
          return false if current_copilot_user_v2.nil?
          return false unless (
            # Show to org admins who have access to Copilot Business
            (current_copilot_user_v2.has_cb_access? && current_user.owned_organizations.where(plan: GitHub::Plan.business.name).count > 0) ||
            # Show to GHEC admins who have access to Copilot Business or Enterprise
            ((current_copilot_user_v2.has_cb_access? || current_copilot_user_v2.has_ce_access?) && current_user.businesses(membership_type: :admin).count > 0) ||
            # Show to Copilot Business users who have preview features enabled
            (current_copilot_user_v2.has_cb_access? && current_copilot_user_v2.editor_preview_features_enabled?) ||
            # Show to Copilot Free users who are not part of any GHEC organizations
            (current_copilot_user_v2.has_limited_access? && current_user.businesses(membership_type: :org_membership).count == 0) ||
            # Show to Copilot Pro users (paid or trial) who are not part of any GHEC organizations
            ((current_copilot_user_v2.has_paid_ci_access? || current_copilot_user_v2.has_trial_access?) && current_user.businesses(membership_type: :org_membership).count == 0)
          )
          true # Default to showing. In tests it will not show without this
        }
      },
      {
        feature: :dashboard_copilot_agent_mode_launch_nudge_step_2,
        notice: :dashboard_copilot_agent_mode_launch_nudge_step_2,
        partial: "dashboard/promos/copilot_agent_mode_launch_step_2",
        extra_condition: -> {
          return false if !current_user.feature_enabled?(:dashboard_copilot_agent_mode_launch_nudge_step_2)
          return false if GitHub.multi_tenant_enterprise? || current_user&.is_enterprise_managed? || GitHub.enterprise?
          return false unless current_user.subscribed_to_in_product_messages?
          return false if current_copilot_user_v2.nil?
          return false unless current_user.interacted_with_a_nudge(id: :dashboard_copilot_agent_mode_launch_nudge, before: 1.day.ago, type: :click)
          return false unless (
            # Show to org admins who have access to Copilot Business
            (current_copilot_user_v2.has_cb_access? && current_user.owned_organizations.where(plan: GitHub::Plan.business.name).count > 0) ||
            # Show to GHEC admins who have access to Copilot Business or Enterprise
            ((current_copilot_user_v2.has_cb_access? || current_copilot_user_v2.has_ce_access?) && current_user.businesses(membership_type: :admin).count > 0) ||
            # Show to Copilot Business users who have preview features enabled
            (current_copilot_user_v2.has_cb_access? && current_copilot_user_v2.editor_preview_features_enabled?) ||
            # Show to Copilot Free users who are not part of any GHEC organizations
            (current_copilot_user_v2.has_limited_access? && current_user.businesses(membership_type: :org_membership).count == 0) ||
            # Show to Copilot Pro users (paid or trial) who are not part of any GHEC organizations
            ((current_copilot_user_v2.has_paid_ci_access? || current_copilot_user_v2.has_trial_access?) && current_user.businesses(membership_type: :org_membership).count == 0)
          )
          true # Default to showing. In tests it will not show without this
        }
      },
      {
        feature: :dashboard_copilot_agent_mode_launch_nudge_step_3,
        notice: :dashboard_copilot_agent_mode_launch_nudge_step_3,
        partial: "dashboard/promos/copilot_agent_mode_launch_step_3",
        extra_condition: -> {
          return false if !current_user.feature_enabled?(:dashboard_copilot_agent_mode_launch_nudge_step_3)
          return false if GitHub.multi_tenant_enterprise? || current_user&.is_enterprise_managed? || GitHub.enterprise?
          return false unless current_user.subscribed_to_in_product_messages?
          return false if current_copilot_user_v2.nil?
          return false unless current_user.interacted_with_a_nudge(id: :dashboard_copilot_agent_mode_launch_nudge_step_2, before: 7.days.ago, type: :click)
          return false unless (
            # Show to org admins who have access to Copilot Business
            (current_copilot_user_v2.has_cb_access? && current_user.owned_organizations.where(plan: GitHub::Plan.business.name).count > 0) ||
            # Show to GHEC admins who have access to Copilot Business or Enterprise
            ((current_copilot_user_v2.has_cb_access? || current_copilot_user_v2.has_ce_access?) && current_user.businesses(membership_type: :admin).count > 0) ||
            # Show to Copilot Business users who have preview features enabled
            (current_copilot_user_v2.has_cb_access? && current_copilot_user_v2.editor_preview_features_enabled?) ||
            # Show to Copilot Free users who are not part of any GHEC organizations
            (current_copilot_user_v2.has_limited_access? && current_user.businesses(membership_type: :org_membership).count == 0) ||
            # Show to Copilot Pro users (paid or trial) who are not part of any GHEC organizations
            ((current_copilot_user_v2.has_paid_ci_access? || current_copilot_user_v2.has_trial_access?) && current_user.businesses(membership_type: :org_membership).count == 0)
          )
          true # Default to showing. In tests it will not show without this
        }
      }
    ]
  end
end
