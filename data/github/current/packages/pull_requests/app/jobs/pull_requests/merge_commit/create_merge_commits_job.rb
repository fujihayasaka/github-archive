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

      RepoRepairingError = Class.new(StandardError)

      use_primaries ApplicationRecord::IssuesPullRequests

      use_replicas ApplicationRecord::Collab,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Repositories,
        ApplicationRecord::Spokes,
        ApplicationRecord::Mysql1,
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
        first_enqueued_at = T.let(job.initially_enqueued_at, Time)
        duration = job.initially_enqueued_at ? Time.now - first_enqueued_at : 0.0

        GitHub.logger.info(job.logging_context.merge({
          "gh.merge_commits.feature": "create_commits",
          "gh.merge_commits.create_commits.invalid_reason": "job_failed_retries_exhausted",
          "gh.job.name": job.class.name,
          "gh.job.attempts": job.executions,
          "exception.type": error.class.name,
          "exception.message": error.message,
          "total_duration": duration,
        }))

        # TODO: Track total duration metrics.
        GitHub.dogstats.increment("pull_requests.merge_commits.create_commits.retries_exhausted")
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
        GitHub.logger.with_named_tags("gh.pull_request.id": pull_request.id, "gh.repo.id": pull_request.repository_id) do
          unless repository = pull_request.repository
            return track("missing_repository")
          end

          if repository.repairing?
            track("repository_repairing")
            raise RepoRepairingError
          end

          if repository.feature_enabled?(:disable_merge_commit_create_commits_jobs)
            return track("feature_disabled")
          end

          with_restraint(repository) do
            CreateCommits::Service.new(
              pull_request:,
              priority:,
              requested_at: initially_enqueued_at,
            ).call
          end
        end
      end

      private

      # Max concurrency of our this job, per Repository.
      MAX_CONCURRENT = 50

      # The lifespan of the rate limit count. If not queried within this span, we restart
      # the rate limit count from 0 concurrent processes.
      #
      # This should be kept at a value greater than the wait for the `UnableToLock` retry
      # plus the max sum of the time for all the related git operations inside the. As we
      # don't have a known firm value for this, we will go with something we believe should
      # be large enough in most cases.
      #
      # TODO: We've discovered 1 to 2 minute commit generation times, but this previous value
      # _was_ working well enough for the legacy CPRMC job.
      RATE_LIMITER_TTL = T.let(30.seconds.to_i, Integer)

      sig { params(repository: Repository, block: T.proc.void).void }
      def with_restraint(repository, &block)
        restraint = GitHub::Restraint.new

        lock_key = "pull-requests-create-commits-job:#{repository.id}"

        concurrency = if repository.feature_enabled?(:cprmc_half_concurrency)
          (MAX_CONCURRENT / 2).to_i
        else
          MAX_CONCURRENT
        end

        restraint.lock!(lock_key, concurrency, RATE_LIMITER_TTL) { yield }
      end

      sig { params(name: String).void }
      def track(name)
        GitHub.logger.info({ "gh.merge_commits.create_commits.skipped_reason" => name })
        GitHub.dogstats.increment("pull_requests.merge_commits.create_commits.#{name}")
      end
    end
  end
end
