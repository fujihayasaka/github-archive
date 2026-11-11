# typed: strict
# frozen_string_literal: true

class BusinessOrchestrationJob < OrchestrationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  queue_as :business_orchestration

  sig { params(orchestration_id: Integer, type: String, kicked: T::Boolean).void }
  def perform(orchestration_id, type, kicked: false)
    klass = type.constantize
    orchestration = T.let(nil, T.untyped)
    # read from master to avoid replication lag like the parent OrchestrationJob.
    with_write do
      orchestration = klass.find(orchestration_id)
    end

    orchestration.execute

    if kicked
      GitHub.dogstats.increment("#{orchestration.base_orchestration_name}.kick_finish", tags: ["type:#{orchestration.type}", "state:#{orchestration.state}"])
    end
  end
end
