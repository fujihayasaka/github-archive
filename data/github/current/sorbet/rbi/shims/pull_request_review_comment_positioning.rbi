# frozen_string_literal: true
# typed: strict

# Shim for dynamically delegated positioning attributes on PullRequestReviewComment.
# These are defined via `POSITIONING_ATTRS.each { |attr| delegate attr, to: :loaded_pull_request_review_thread }`
# in packages/pull_requests/app/models/pull_request_review_comment.rb but are not
# detected by tapioca's DSL compilers.
class PullRequestReviewComment
  sig { returns(T.nilable(String)) }
  def path; end
end
