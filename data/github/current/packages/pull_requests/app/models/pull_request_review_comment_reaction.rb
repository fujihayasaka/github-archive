# typed: true
# frozen_string_literal: true

# Emoji-ish reactions that can be attached to PullRequestReviewComments.
class PullRequestReviewCommentReaction < ApplicationRecord::Domain::IssuesPullRequests
  include Reaction::Common

  validate :comment_can_be_reacted, on: :create

  def comment_can_be_reacted
    if pull_request_review_comment&.code_scanning? || pull_request_review_comment&.code_quality?
      errors.add(:base, "code scanning/quality comments cannot have reactions")
      return false
    end

    true
  end
end
