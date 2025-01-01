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
          return false if !current_user.feature_flag_enabled?(:dashboard_onboarding_copilot_free_nudge, default: false)
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
    copilot_user = context[:copilot_user]
    [
      {
        feature: :dashboard_onboarding_copilot_free_oss_nudge,
        notice: :dashboard_onboarding_copilot_free_oss_nudge,
        partial: "dashboard/promos/copilot_free_oss",
        extra_condition: -> {
          return false if !current_user.feature_flag_enabled?(:dashboard_onboarding_copilot_free_oss_nudge, default: false)
          return false if GitHub.multi_tenant_enterprise? || current_user.is_enterprise_managed? || GitHub.enterprise?
          return false unless current_user.subscribed_to_in_product_messages?
          # Return false if they have access to any form of copilot that isn't Free Copilot limited
          return false if current_copilot_user_v2&.has_paid_access? || current_copilot_user_v2&.has_free_pro_access? || current_copilot_user_v2&.has_trial_access? || current_copilot_user_v2&.has_limited_access? || current_copilot_user_v2&.has_cb_access? || current_copilot_user_v2&.has_ce_access?
          # Show if the user qualifies as engaged OSS and is not already on a free Copilot subscription
          true if Copilot::FreeUser.is_engaged_oss_user?(copilot_user) && !T.must(Copilot::FreeUser.find_for_copilot_user(copilot_user)).subscribed?
        }
      },
      {
        feature: :github_universe_2025_dashboard_nudge,
        notice: :github_universe_2025_dashboard_nudge,
        partial: "dashboard/promos/github_universe_2025",
        extra_condition: -> {
          return false unless current_user.feature_flag_enabled?(:github_universe_2025_dashboard_nudge, default: false)
          return false if GitHub.multi_tenant_enterprise? || current_user&.is_enterprise_managed? || GitHub.enterprise?
          return false unless current_user.subscribed_to_in_product_messages?

          # Do not show to users in an active DFD trial
          return false if current_user.businesses.any? do |business|
            business.dfd_trial? && business.trial_expires_at && business.trial_expires_at >= Time.current
          end

          true
        }
      },
      {
        feature: :dashboard_spark_public_preview_nudge,
        notice: :dashboard_spark_public_preview_nudge,
        partial: "dashboard/promos/spark_public_preview",
        extra_condition: -> {
          return false unless current_user.feature_flag_enabled?(:dashboard_spark_public_preview_nudge, default: false)
          return false if GitHub.multi_tenant_enterprise? || current_user&.is_enterprise_managed? || GitHub.enterprise?
          return false unless current_user.subscribed_to_in_product_messages?

          # Do not show to users in an active DFD trial
          return false if current_user.businesses.any? do |business|
            business.dfd_trial? && business.trial_expires_at && business.trial_expires_at >= Time.current
          end

          # User segment targeting: Copilot Pro+ users
          return false unless current_copilot_user_v2&.has_pro_plus_access?

          true
        }
      }
    ]
  end
end
