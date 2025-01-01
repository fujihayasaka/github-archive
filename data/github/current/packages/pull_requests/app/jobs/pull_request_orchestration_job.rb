# typed: true
# frozen_string_literal: true

class PullRequestOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :pull_request_orchestration
end
