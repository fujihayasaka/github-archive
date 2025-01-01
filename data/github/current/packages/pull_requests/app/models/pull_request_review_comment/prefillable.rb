# typed: true
# frozen_string_literal: true

module PullRequestReviewComment::Prefillable
  extend ActiveSupport::Concern

  class_methods do
    # Public: Preloads #pull_request and #user associations in
    # PullRequestReviewComment objects.
    #
    # comments - An Array of PullRequestReviewComment objects.
    #
    # Optional keyword args to configure what assocations to load.
    #     issue: - Issue to prevent re-fetching the Issue
    #              when preloading PullRequest associations.
    #     repository: - Repository to prevent re-fetching
    #
    # Returns nothing.
    def prefill_associations(comments, issue: nil, repository: nil)
      associations_to_prefill = [{ latest_user_content_edit: :editor }, :pull_request, :repository, :user, :pull_request_review_thread]
      GitHub::PrefillAssociations.prefill_associations(comments, associations_to_prefill, available_records: [repository])
      PullRequest.prefill_associations(comments.map(&:pull_request), issues: [issue])
    end
  end
end
