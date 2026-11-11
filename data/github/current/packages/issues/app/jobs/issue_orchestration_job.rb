# typed: true
# frozen_string_literal: true

class IssueOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :issue_orchestration

  # Tenant is resolved from repo during orchestration.execute
  # https://github.com/github/github/blob/master/packages/repositories/app/models/orchestration.rb#L295
  exempt_from_tenant_context_requirement

  def perform(orchestration_id, type, kicked: false)
    return super unless FeatureFlag.vexi.enabled?("issue_orchestration_job_replica_reads", default: false)

    klass = type.constantize
    orchestrator = klass.find(orchestration_id)
    orchestrator.execute

    if kicked
      GitHub.dogstats.increment("#{orchestrator.base_orchestration_name}.kick_finish", tags: ["type:#{orchestrator.type}", "state:#{orchestrator.state}"])
    end
  end
end
