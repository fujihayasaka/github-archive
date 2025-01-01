# typed: true
# frozen_string_literal: true

class IssueCommentOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :issue_comment_orchestration
end
