# typed: true
# frozen_string_literal: true

module PullRequests::MergeboxHelper
  include GitHub::ResilienceMixin

  def new_mergebox_feature_enabled_for_user?(user, params)
    if GitHub.enterprise?
      GitHub.react_merge_box_enabled?
    else
      !user&.feature_flag_enabled?(:new_merge_box_ga_bypass_override, default: false)
    end
  end

  def default_merge_method_for_user(pull, user)
    merge_requirements = PullRequest::MergeRequirements.new(pull, nil, nil, nil, user)
    with_async_database_error_fallback(
      merge_requirements.merge_method,
      fallback: :MERGE
    ).sync.upcase
  end
end
