# typed: true
# frozen_string_literal: true

class IssueCommentOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :issue_comment_orchestration

  def perform(orchestration_id, type, kicked: false)
    return super unless FeatureFlag.vexi.enabled?("issue_comment_orchestration_job_replica_reads", default: false)

    klass = type.constantize
    orchestrator = klass.find(orchestration_id)
    orchestrator.execute

    if kicked
      GitHub.dogstats.increment("#{orchestrator.base_orchestration_name}.kick_finish", tags: ["type:#{orchestrator.type}", "state:#{orchestrator.state}"])
    end
  end
end
