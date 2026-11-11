# frozen_string_literal: true

module PrioritizedJobs
  module StartUpdateJob
    def self.perform_later(job, wait: 0)
      priority_class(job).set(wait: wait).perform_later(job)
    end

    def self.perform_now(job)
      priority_class(job).perform_now(job)
    end

    def self.priority_class(job)
      # a pessimistic approach to determine if actions are fully enabled
      # We may enqueue more jobs than necessary on p3 due to this check
      # But, we avoid a synchronous twirp call by checking this in the DB
      unless UpdateJob.where(update_config: job.repo.update_configs).where.not(actions_workflow_run_id: nil).exists?
        return Low
      end

      case job.trigger_type
      when *UpdateJob::P1_TRIGGER_TYPES
        High
      when *UpdateJob::P4_TRIGGER_TYPES
        Graph
      else
        Default
      end
    end
  end
end
