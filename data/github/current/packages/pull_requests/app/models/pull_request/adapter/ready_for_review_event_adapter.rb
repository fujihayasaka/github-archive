# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::ReadyForReviewEventAdapter < PullRequest::Adapter::IssueEventAdapter
  READY_FOR_REVIEW_EVENT = "ReadyForReviewEvent"
end
