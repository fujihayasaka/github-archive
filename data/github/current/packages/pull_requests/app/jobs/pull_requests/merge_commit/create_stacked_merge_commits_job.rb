# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    class CreateStackedMergeCommitsJob < ApplicationJob
      include ActiveJob::InitiallyEnqueuedAt
      include RestrainedMergeCommitCreation

      RepoRepairingError = Class.new(StandardError)

      use_primaries ApplicationRecord::IssuesPullRequests

      use_replicas ApplicationRecord::Collab,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::Spokes,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Permissions,
        ApplicationRecord::Iam,
        ApplicationRecord::RepositoriesActionsChecks,
        allow_replication_lag: [
          ApplicationRecord::Configurations
        ]

      queue_as :pull_request_create_merge_commits

      retry_on_dirty_exit

      RETRYABLE_ERRORS = T.let([
        RepoRepairingError,
        GitHub::Restraint::UnableToLock,
      ].freeze, T::Array[T.untyped])

      T.unsafe(self).retry_on(*RETRYABLE_ERRORS, wait: proc { rand(6..12) }, attempts: 20) do |job, error|
        job = T.cast(job, CreateStackedMergeCommitsJob)
        first_enqueued_at = T.let(job.initially_enqueued_at, T.nilable(Time))
        duration = first_enqueued_at ? Time.now - first_enqueued_at : 0.0

        GitHub.logger.info({
          "gh.merge_commits.feature": "create_commits",
          "gh.merge_commits.stacked": true,
          "gh.#{CreateStackedCommits::Service::CREATE_COMMITS}.invalid_reason": "job_failed_retries_exhausted",
          "gh.job.name": job.class.name,
          "gh.job.attempts": job.executions,
          "exception.type": error.class.name,
          "exception.message": error.message,
          "total_duration": duration,
        })

        GitHub.dogstats.increment("pull_requests.#{CreateStackedCommits::Service::CREATE_COMMITS}.retries_exhausted")
      end

      resolve_tenant_context do |stack_id|
        if stack = PullRequests::Stack.find_by(id: stack_id)
          if repository = T.cast(stack.repository, T.nilable(Repository)) # rubocop:disable GitHub/AvoidCast
            Business.find_by(id: repository.tenant_id)
          end
        end
      end

      locked_by timeout: 5.minutes, key: ->(job) do
        stack_id = job.arguments.first
        "prs-create-stacked-merge-commits-#{stack_id}"
      end

      sig { params(stack_id: Integer, priority: Integer).void }
      def perform(stack_id, priority: 0)
        unless stack = PullRequests::Stack.find_by(id: stack_id)
          return track("missing_stack")
        end

        PullRequests::Observability::Git.tag(repository: T.cast(stack.repository, T.nilable(Repository)), feature: :create_stacked_merge_commits) do # rubocop:disable GitHub/AvoidCast
          GitHub.logger.with_named_tags("gh.stack.id": stack.id, "gh.repo.id": stack.repository_id, "gh.merge_commits.feature": "create_commits", "gh.merge_commits.stacked": true) do
            unless repository = T.cast(stack.repository, T.nilable(Repository)) # rubocop:disable GitHub/AvoidCast
              return track("missing_repository")
            end

            if repository.repairing?
              track("repository_repairing")
              raise RepoRepairingError
            end

            if repository.feature_flag_enabled?(:disable_merge_commit_create_commits_jobs, default: false)
              return track("feature_disabled")
            end

            with_restraint(repository) do
              CreateStackedCommits::Service.new(
                stack:,
                priority:,
                requested_at: initially_enqueued_at,
              ).call
            end
          end
        end
      end

      private

      sig { params(name: String).void }
      def track(name)
        GitHub.logger.info({ "gh.merge_commits.stacked" => true, "gh.#{CreateStackedCommits::Service::CREATE_COMMITS}.outcome" => name })
        GitHub.dogstats.increment("pull_requests.#{CreateStackedCommits::Service::CREATE_COMMITS}.outcome", tags: ["outcome:#{name}"])
      end
    end
  end
end
