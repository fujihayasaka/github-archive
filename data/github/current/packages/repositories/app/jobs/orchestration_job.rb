# typed: true
# frozen_string_literal: true

class OrchestrationJob < ApplicationJob # rubocop:todo GitHub/KubeJobsRetryOnDirtyExit
  # Default to repo orchestration queue if not explicitly set in subclass
  queue_as :repository_orchestration

  # the job should give up when the orchestration throws this exception
  discard_on Orchestration::MaxAttemptsError

  # This job should not be the one that decides when to give up retrying, that's the orchestration's role.
  # The orchestration will raise MaxAttemptsError when it has reached Orchestration::MAX_ATTEMPTS.
  # So configure the job to retry a little more than that
  retry_on(*Orchestration::RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: Orchestration::MAX_ATTEMPTS + 1)

  class DirectCallError < StandardError; end

  before_enqueue do
    raise DirectCallError, "OrchestrationJob should not be queued, use subclass instead." if direct_call?
  end

  def direct_call?
    self.class.to_s == "OrchestrationJob"
  end

  def perform(orchestration_id, type, kicked: false)
    raise DirectCallError, "OrchestrationJob should not be called, use subclass instead." if direct_call?

    klass = type.constantize
    with_write do
      # read from master to avoid replication lag
      orchestration = klass.find(orchestration_id)

      orchestration.execute

      if kicked
        GitHub.dogstats.increment("#{orchestration.base_orchestration_name}.kick_finish", tags: ["type:#{orchestration.type}", "state:#{orchestration.state}"])
      end
    end
  end
end
