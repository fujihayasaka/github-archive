# typed: true
# frozen_string_literal: true

module PullRequests::NewFilesChangedHelper
  def new_files_changed_feature_flag_enabled_for_user?(user)
    user&.feature_enabled?(:prx_files)
  end

  def new_files_changed_feature_enabled_for_user?(user, params)
    return false unless new_files_changed_feature_flag_enabled_for_user?(user)

    new_files_changed_query_param = params[:prx_files]
    if new_files_changed_query_param.present?
      return true if new_files_changed_query_param == "true" && !ENV["LUC_PERFORMANCE"].nil?
      return false if new_files_changed_query_param == "false"
    end

    user&.feature_preview_enabled?(:prx_files)
  end
end
