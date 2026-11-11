# typed: strict
# frozen_string_literal: true

module PullRequests
  module MergeCommit
    # This job creates the latest merge commit for the given pull request. As this
    # is needed in order to refresh the merge box or get the latest merge related
    # attributes for a pull request via the APIs, it can have fairly heavy traffic.
    # This is especially true in the case that a pull request is merged to a common
    # base branch, causing the merge commits for all other pull requests in the
    # repository to become out of date.
    #
    # ## Job Restrictions
    #
    # To manage the stampede of merge commit creations caused by such a merge, we have
    # careful and thorough rate limiting in place at multiple levels so that the
    # number of simultaneous merge commit updates to a single repository is kept to
    # minimum.
    #
    # ### 1. Job Locking
    #
    # We lock the job based on the pull request id, This ensures that numerous
    # requests to a single pull request don't flood the queue with identical jobs
    # all trying to do the same thing.
    #
    # ### 2. Resource Locking
    #
    # We utilize GitHub::Restraint to limit the number of concurrent jobs on a single
    # repository. This helps busy monorepos with many developers working simultaneously,
    # or with bots responding to web hooks. With this limit, some jobs may be delayed
    # but we shouldn't have so many that other jobs or user pushes are rejected.
    #
    # ### 3. Retries
    #
    # When the resource is locked, or the git repo is just too busy, we retry the job
    # a limited number of times with a delay. If all the attempts are spent, the pull
    # request will remain in an undefined mergeable state until the user re-initiates
    # a merge commit calculation request.
    class CreateMergeCommitsJob < ApplicationJob
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
        job = T.cast(job, CreateMergeCommitsJob)
        first_enqueued_at = T.let(job.initially_enqueued_at, Time)
        duration = job.initially_enqueued_at ? Time.now - first_enqueued_at : 0.0

        GitHub.logger.info(job.send(:logging_context).merge({
          "gh.merge_commits.feature": "create_commits",
          "gh.#{CreateCommits::Service::CREATE_COMMITS}.invalid_reason": "job_failed_retries_exhausted",
          "gh.job.name": job.class.name,
          "gh.job.attempts": job.executions,
          "gh.repo.id": job.arguments.first.repository_id,
          "exception.type": error.class.name,
          "exception.message": error.message,
          "total_duration": duration,
        }))

        GitHub.dogstats.increment("pull_requests.#{CreateCommits::Service::CREATE_COMMITS}.retries_exhausted")
      end

      resolve_tenant_context do |pull_request|
        if repository = pull_request.repository
          Business.find_by(id: repository.tenant_id)
        end
      end

      locked_by timeout: 5.minutes, key: ->(job) do
        pull_request_id = job.arguments.first.id
        "prs-create-merge-commits-#{pull_request_id}"
      end

      sig { params(pull_request: PullRequest, priority: Integer).void }
      def perform(pull_request, priority: 0)
        PullRequests::Observability::Git.tag(repository: pull_request.repository, feature: :mcr_create_merge_commits_job) do
          perform_inner(pull_request, priority: priority)
        end
      end

      private

      sig { params(pull_request: PullRequest, priority: Integer).void }
      def perform_inner(pull_request, priority:)
        GitHub.logger.with_named_tags("gh.pull.id": pull_request.id, "gh.repo.id": pull_request.repository_id, "gh.merge_commits.feature": "create_commits") do
          unless repository = pull_request.repository
            return track("missing_repository")
          end

          age_in_hours = (Time.current - pull_request.updated_at) / 1.hour
          GitHub.dogstats.distribution("pull_request.create_merge_commit_jobs.dist.pull_request_age", age_in_hours)

          if repository.repairing?
            track("repository_repairing")
            raise RepoRepairingError
          end

          if repository.feature_flag_enabled_or_raise?(:disable_merge_commit_create_commits_jobs) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
            return track("feature_disabled")
          end

          create_merge = T.let(nil, T.nilable(CreateCommits::Service::ReturnValue))

          with_restraint(repository) do
            create_merge = CreateCommits::Service.new(
              pull_request:,
              priority:,
              requested_at: initially_enqueued_at,
            ).call
          end

          if FeatureFlag.vexi.enabled?(:compare_stale_merge_job_enabled, repository, default: false)
            if create_merge.is_a?(PullRequests::MergeCommit::CreateCommits::Result)
              merge_commit = create_merge.merge_commit

              if merge_commit.is_a?(Entity::Commits::Created) || merge_commit.is_a?(Entity::Commits::Reused) || merge_commit.is_a?(Entity::Commits::Cacheable)
                # Possibly queue a comparison job to run in the future -- depending on FF settings.
                CompareStaleMergeCommitJob.queue_future_run(pull_request:, merge_sha: merge_commit.sha)
              end
            end
          end
        end
      end

      sig { params(name: String).void }
      def track(name)
        GitHub.logger.info({ "gh.#{CreateCommits::Service::CREATE_COMMITS}.outcome" => name })
        GitHub.dogstats.increment("pull_requests.#{CreateCommits::Service::CREATE_COMMITS}.result_commit", tags: ["type:merge", "outcome:#{name}"])
        GitHub.dogstats.increment("pull_requests.#{CreateCommits::Service::CREATE_COMMITS}.result_commit", tags: ["type:rebase", "outcome:#{name}"])
        GitHub.dogstats.increment("pull_requests.#{CreateCommits::Service::CREATE_COMMITS}.outcome", tags: ["outcome:#{name}"])
      end
    end
  end
end
