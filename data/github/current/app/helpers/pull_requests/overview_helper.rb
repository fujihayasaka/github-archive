# typed: true
# frozen_string_literal: true

module PullRequests::OverviewHelper
  def pr_overview_feature_flag_enabled_for_user?(user)
    if user.nil?
      false
    else
      user.feature_flag_enabled?(:prs_overview_react, default: false)
    end
  end

  def pr_overview_feature_enabled_for_user?(user, params)
    return false unless pr_overview_feature_flag_enabled_for_user?(user)

    overview_query_param = params[:overview]
    if overview_query_param.present?
      return true if overview_query_param == "true"
      return false if overview_query_param == "false"
    end

    user.feature_preview_enabled?(:prs_overview_react)
  end
end
