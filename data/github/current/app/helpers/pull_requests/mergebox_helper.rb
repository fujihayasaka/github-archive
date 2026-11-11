# typed: true
# frozen_string_literal: true

module PullRequests::MergeboxHelper
  include GitHub::ResilienceMixin

  def default_merge_method_for_user(pull, user)
    return pull.repository.default_merge_method_for(user).upcase if user.nil?

    merge_requirements = PullRequest::MergeRequirements.new(pull, nil, nil, nil, user)
    with_async_database_error_fallback(
      merge_requirements.merge_method,
      fallback: :MERGE
    ).sync.upcase
  end
end
