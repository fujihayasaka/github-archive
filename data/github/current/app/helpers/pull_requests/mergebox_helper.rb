# typed: true
# frozen_string_literal: true

module PullRequests::MergeboxHelper
  extend T::Sig

  MERGEBOX_QUERY = Rails.root.join("ui/packages/mergebox/hooks/__generated__/useLoadMergeBoxQuery.graphql.ts")

  def new_mergebox_feature_flag_enabled_for_user?(user)
    user&.feature_enabled?(:mergebox_react_partial)
  end

  def new_mergebox_feature_enabled_for_user?(user, params)
    return false unless new_mergebox_feature_flag_enabled_for_user?(user)

    new_mergebox_query_param = params[:new_mergebox]
    if new_mergebox_query_param.present?
      return true if new_mergebox_query_param == "true"
      return false if new_mergebox_query_param == "false"
    end

    user&.feature_preview_enabled?(:mergebox_react_partial)
  end

  def read_from_mergebox_json_api_enabled_for_user?(user)
    user&.feature_enabled?(:read_from_mergebox_json_api)
  end

  def default_merge_method_for_user(pull, user)
    Platform::Models::PullRequestMergeRequirements.new(pull, nil, nil, nil, user).merge_method.sync.upcase
  end
end
