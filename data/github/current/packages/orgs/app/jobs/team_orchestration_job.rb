# typed: strict
# frozen_string_literal: true

class TeamOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :team_orchestration
end
