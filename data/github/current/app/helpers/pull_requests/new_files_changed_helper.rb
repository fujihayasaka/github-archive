# typed: true
# frozen_string_literal: true

module PullRequests::NewFilesChangedHelper
  def new_files_changed_feature_flag_enabled_for_user?(user)
    if user.nil?
      # For anonymous users, check the global anonymous prx files feature flag
      FeatureFlag.vexi.enabled?(:pr_files_anon, default: false)
    else
      user.feature_flag_enabled?(:prx_files, default: false)
    end
  end

  def new_files_changed_feature_enabled_for_user?(user, params)
    return false unless new_files_changed_feature_flag_enabled_for_user?(user)

    new_files_changed_query_param = params[:new_files_changed]
    if new_files_changed_query_param.present?
      return true if new_files_changed_query_param == "true"
      return false if new_files_changed_query_param == "false"
    end

    # For anonymous users, if the pr_files_anon flag is enabled, return true
    return true if user.nil?

    user.feature_preview_enabled?(:prx_files, enrolled_by_default_override: user.feature_flag_enabled_or_raise?(:prx_files_opt_out_by_default)) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
  end

  def new_files_changed_show_opt_in?(user, params)
    new_files_changed_feature_flag_enabled_for_user?(user) && !new_files_changed_feature_enabled_for_user?(user, params)
  end

  def unified_changes_route_enabled?(user, params)
    new_files_changed_feature_enabled_for_user?(user, params)
  end
end
