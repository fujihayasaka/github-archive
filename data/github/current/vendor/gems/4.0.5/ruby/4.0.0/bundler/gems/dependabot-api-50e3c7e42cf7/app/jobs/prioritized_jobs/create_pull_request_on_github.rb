# frozen_string_literal: true

module PrioritizedJobs
  module CreatePullRequestOnGitHub
    def self.perform_later(pending_pr:)
      case pending_pr.update_job.trigger_type
      when *UpdateJob::PULL_REQUEST_TRIGGER_TYPES_P1
        High.perform_later(pending_pr: pending_pr)
      when *UpdateJob::PULL_REQUEST_TRIGGER_TYPES_P3
        Low.perform_later(pending_pr: pending_pr)
      else
        Default.perform_later(pending_pr: pending_pr)
      end
    end
  end
end
