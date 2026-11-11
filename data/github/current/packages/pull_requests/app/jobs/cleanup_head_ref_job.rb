# typed: true
# frozen_string_literal: true

class CleanupHeadRefJob < ApplicationJob
  use_replicas ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql1,
    ApplicationRecord::Spokes,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::RepositoriesPushes

  retry_on_dirty_exit
  queue_as :cleanup_head_ref

  MAX_ATTEMPTS = 3
  RETRYABLE_ERRORS = [
    GitHub::DGit::ThreepcError,
    GitHub::DGit::ThreepcBusyError,
    GitHub::DGit::ThreepcFailedToLock,
  ].freeze

  retry_on *RETRYABLE_ERRORS, attempts: MAX_ATTEMPTS do |job, error|
    GitHub.logger.info({
      "gh.pull_request.merge.cleanup_head_ref.outcome": "job_failed_retries_exhausted",
      "gh.job.name": job.class.name,
      "gh.job.attempts": job.executions,
      "exception.type": error.class.name,
      "exception.message": error.message,
    })

    GitHub.dogstats.increment("pull_request.merge.cleanup_head_ref_job.retries_exhausted")
  end

  sig { params(pull_request_id: Integer, actor_id: Integer, reflog_data: Hash).void }
  def perform(pull_request_id, actor_id, reflog_data = {})
    logger = PullRequests::Shared::Logger.new(default_prefix: "gh.pull_request.merge.cleanup_head_ref_job", feature: "merge")

    pull = PullRequest.find_by(id: pull_request_id)
    unless pull
      logger.append({ outcome: "return_no_pull_request" })
      logger.flush
      return
    end

    logger.append_pull_request_context(pull)

    actor = User.find_by(id: actor_id)
    unless actor
      logger.append({ outcome: "return_no_actor" })
      logger.flush
      return
    end

    pull.cleanup_head_ref(actor, reflog_data:, logger:)
  end
end
