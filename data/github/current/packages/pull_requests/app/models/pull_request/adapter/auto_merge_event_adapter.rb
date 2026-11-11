# typed: true
# frozen_string_literal: true

class PullRequest::Adapter::AutoMergeEventAdapter < PullRequest::Adapter::IssueEventAdapter
  AUTO_MERGE_DISABLED_EVENT = "AutoMergeDisabledEvent"
  AUTO_MERGE_ENABLED_EVENT  = "AutoMergeEnabledEvent"
  AUTO_SQUASH_ENABLED_EVENT = "AutoSquashEnabledEvent"
  AUTO_REBASE_ENABLED_EVENT = "AutoRebaseEnabledEvent"
end
