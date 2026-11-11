# typed: strict
# frozen_string_literal: true

class RepositoryOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :repository_orchestration
end
