# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::ConvertToDraftEventAdapter < PullRequest::Adapter::IssueEventAdapter
  CONVERT_TO_DRAFT_EVENT = "ConvertToDraftEvent"
end
