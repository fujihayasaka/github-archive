# typed: true
# frozen_string_literal: true

module PullRequests::MergeboxHelper
  include GitHub::ResilienceMixin
  MERGEBOX_QUERY = Rails.root.join("ui/packages/mergebox/hooks/__generated__/useLoadMergeBoxQuery.graphql.ts")

  def new_mergebox_feature_flag_enabled_for_user?(user)
    # Don't auto return if user has admin bypass override of merge box GA
    return true if user&.feature_enabled?(:new_merge_box_ga) && !user&.feature_enabled?(:new_merge_box_ga_bypass_override)
    user&.feature_enabled?(:mergebox_react_partial)
  end

  def new_mergebox_feature_enabled_for_user?(user, params)
    # Don't auto return if user has admin bypass override of merge box GA
    return true if user&.feature_enabled?(:new_merge_box_ga) && !user&.feature_enabled?(:new_merge_box_ga_bypass_override)
    return false unless new_mergebox_feature_flag_enabled_for_user?(user)

    new_mergebox_query_param = params[:new_mergebox]
    if new_mergebox_query_param.present?
      return true if new_mergebox_query_param == "true"
      return false if new_mergebox_query_param == "false"
    end

    user&.feature_preview_enabled?(:mergebox_react_partial, enrolled_by_default_override: user&.feature_enabled?(:new_merge_experience_opt_out_by_default))
  end

  def default_merge_method_for_user(pull, user)
    merge_requirements = PullRequest::MergeRequirements.new(pull, nil, nil, nil, user)
    with_async_database_error_fallback(
      merge_requirements.merge_method,
      fallback: :MERGE
    ).sync.upcase
  end
end
