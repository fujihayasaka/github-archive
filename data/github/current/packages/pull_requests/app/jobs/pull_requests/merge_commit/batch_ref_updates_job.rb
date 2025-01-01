# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    class BatchRefUpdatesJob < ApplicationJob
      use_primaries ApplicationRecord::IssuesPullRequests

      use_replicas ApplicationRecord::Collab,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::Spokes,
        ApplicationRecord::Mysql1

      queue_as :pull_request_batch_ref_updates

      RepoRepairingError = Class.new(StandardError)

      RETRYABLE_ERRORS = T.let([
        RepoRepairingError,
      ].freeze, T::Array[T.untyped])

      T.unsafe(self).retry_on(*RETRYABLE_ERRORS, wait: 5.seconds, attempts: 10) do |job, error|
        job = T.cast(job, BatchRefUpdatesJob)

        GitHub.logger.info(job.send(:logging_context).merge({
          "gh.merge_commits.feature": "batch_ref_updates",
          "gh.#{BatchRefUpdates::Service::BATCH_REF_UPDATES}.invalid_reason": "job_failed_retries_exhausted",
          "gh.job.name": job.class.name,
          "gh.job.attempts": job.executions,
          "exception.type": error.class.name,
          "exception.message": error.message,
        }))

        GitHub.dogstats.increment("pull_requests.#{BatchRefUpdates::Service::BATCH_REF_UPDATES}.retries_exhausted")
      end

      retry_on_dirty_exit

      resolve_tenant_context do |repository|
        if repository = T.let(repository, T.nilable(Repository))
          Business.find_by(id: repository.tenant_id)
        end
      end

      locked_by timeout: 5.minutes, key: ->(job) do
        repository_id = job.arguments.first.id
        "prs-batch-update-refs#{repository_id}"
      end

      sig { params(repository: Repository).void }
      def perform(repository)
        GitHub.logger.with_named_tags("gh.repo.id": repository.id, "gh.merge_commits.feature": "batch_ref_updates") do
          if repository.repairing?
            track("repository_repairing")
            raise RepoRepairingError
          end

          if repository.feature_flag_enabled_or_raise?(:disable_merge_commit_create_commits_jobs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return track("feature_disabled")
          end
        end

        # Execute the end to end process.
        BatchRefUpdates::Service.new(repository:, batch_size: 10).call

        # Once the job has finished, clear the lock so the job could be enqueued in parallel.
        clear_lock

        # Determine if there are remaining merge commit requests, and immediately invoke the job to prevent
        # halting of the batch updating process.
        request_count = MergeCommitRequest.where(repository_id: repository.id).count

        if request_count > 0
          begin
            self.class.perform_later(repository)
          rescue *Command::ACTIVE_JOB_ERRORS => exception
            # Locks failing to acquire is fine, something else will enqueue this.
          end
        end

        GitHub.dogstats.count("gh.#{BatchRefUpdates::Service::BATCH_REF_UPDATES}_job.remaining_count", request_count)
      end

      sig { params(name: String).void }
      def track(name)
        GitHub.logger.info({ "gh.#{BatchRefUpdates::Service::BATCH_REF_UPDATES}.outcome" => name })
        GitHub.dogstats.increment("pull_requests.#{BatchRefUpdates::Service::BATCH_REF_UPDATES}.outcome", tags: ["outcome:#{name}"])
      end
    end
  end
end
