# typed: true
# frozen_string_literal: true

# This job creates the latest merge commit for the given pull request. As this
# is needed in order to refresh the merge box or get the latest merge related
# attributes for a pull request via the APIs, it can have fairly heavy traffic.
# This is especially true in the case that a pull request is merged to a common
# base branch, causing the merge commits for all other pull requests in the
# repository to become out of date.
#
# ## Job Restrictions

# To manage the stampede of merge commit creations caused by such a merge, we have
# careful and thorough rate limiting in place at multiple levels so that the
# number of simultaneous merge commit updates to a single repository is kept to
# minimum.
#
# ### 1. Job Locking
#
# We lock the job based on a custom key consisting of the pull request id,
# base oid, and head oid at the time of enqueue. This ensures that numerous
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

class CreatePullRequestMergeCommitJob < ApplicationJob
  use_primaries ApplicationRecord::IssuesPullRequests

  use_replicas ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Mysql1

  set_max_redelivery_attempts 0

  queue_as :create_pull_request_merge_commit

  resolve_tenant_context do |pull_request_id|
    repository = PullRequest.find_by(id: pull_request_id)&.repository
    if repository
      Business.find_by(id: repository.tenant_id)
    end
  end

  RepoRepairingError = Class.new(StandardError)

  # The maximum number of CreatePullRequestMergeCommit that are
  # allowed to run for a single repository at one time.
  MAX_CONCURRENT = 50

  # The lifespan of the rate limit count. If not queried within this span, we restart
  # the rate limit count from 0 concurrent processes.
  # This should be kept at a value greater than the wait for the `UnableToLock` retry
  # plus the max sum of the time for all the git operations inside the
  # PullRequest#create_merge_commit method. As we don't have a known firm value for this,
  # we will go with something we believe should be large enough in most cases.
  RATE_LIMITER_TTL = 30.seconds

  # Max number of attempts and wait time for all retryable failures
  MAX_ATTEMPTS = 20

  # Wait a random number of seconds within the given range
  RETRY_WAIT_RANGE = 6..12
  RETRY_PROC = proc { rand(RETRY_WAIT_RANGE) }

  # Trivially discard any attempts to enqueue a job when the pull request's commits
  # haven't changed since a previously enqueued job.
  locked_by key: -> (job) { job.commit_lock_key }, timeout: 5.minutes

  # the error or group of errors will have a unique retry count
  RETRYABLE_ERRORS = [
    RepoRepairingError,
    GitHub::Restraint::UnableToLock,
    [GitHub::DGit::ThreepcBusyError, GitHub::DGit::ThreepcFailedToLock]
  ].freeze

  # declare a separate `retry_on` for each error so their counts don't stack
  RETRYABLE_ERRORS.each do |error_class|
    T.unsafe(self).retry_on *Array(error_class), wait: RETRY_PROC, attempts: MAX_ATTEMPTS do |job, error|
      duration = job.first_enqueued_at ? T.cast(Time.now - job.first_enqueued_at, Float) : 0.0 # rubocop:todo GitHub/AvoidCast
      GitHub.logger.info(job.logging_context.merge({
        "code.function": "retries_exhausted",
        "gh.job.name": job.class.name,
        "gh.job.attempts": job.executions,
        "exception.type": error.class.name,
        "exception.message": error.message,
        "total_duration": duration,
      }))
      GitHub.dogstats.increment("pull_request.create_pull_request_merge_commit_retries_exhuasted")
      GitHub.dogstats.distribution("pull_request.create_pull_request_merge_commit.total_duration", duration)
      GitHub.dogstats.distribution("pull_request.create_pull_request_merge_commit_job.dist.duration", duration * 1000, tags: ["duration:retries_exhausted"])
    end
  end

  # The pull request is gone, we don't care about this merge commit any more.
  discard_on ActiveRecord::RecordNotFound

  def perform(pull_request_id)
    raise RepoRepairingError if repo.repairing?

    # Don't run this code path in tests as it's going to break a lot.
    if !Rails.env.test? && repo.feature_enabled?(:use_merge_commit_request_architecture) # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      GitHub.dogstats.increment("pull_request.create_pull_request_merge_commit_job.using_new_architecture")
      return
    end

    unless repo.active?
      GitHub.logger.info("pull_request_create_pull_request_merge_commit_no_repository")
      GitHub.dogstats.increment("pull_request.create_pull_request_merge_commit.no_repository")
      return
    end

    t0 = Time.now
    with_restraint(repo) do
      t1 = Time.now
      mc_sha = pull_request.create_merge_commit(priority: :low)
      t2 = Time.now

      # Tracking PR's where multiple merge bases lead to hidden files in diff
      # See https://github.com/github/github/issues/157084
      track_multiple_merge_base_prs(mc_sha)
      now = Time.now

      stats = {
        wait_until_restrain: first_enqueued_at ? (t0 - first_enqueued_at).to_f * 1000 : 0,
        wait_under_restrain: (t1 - t0) * 1000,
        create_merge_commit_duration: (t2 - t1) * 1000,
        track_multiple_merge_base_prs_duration: (now - t2) * 1000,
        total_duration: first_enqueued_at ? (now - first_enqueued_at).to_f * 1000 : 0,
        retries: executions - 1,
        is_draft: pull_request.draft?,
      }

      age_in_hours = (Time.current - pull_request.updated_at) / 1.hour
      GitHub.dogstats.distribution("pull_request.create_pull_request_merge_commit_job.dist.pull_request_age", age_in_hours)
      GitHub.dogstats.distribution("pull_request.create_pull_request_merge_commit_job.dist.duration", stats[:wait_until_restrain], tags: ["duration:wait_until_restrain"])
      GitHub.dogstats.distribution("pull_request.create_pull_request_merge_commit_job.dist.duration", stats[:wait_under_restrain], tags: ["duration:wait_under_restrain"])
      GitHub.dogstats.distribution("pull_request.create_pull_request_merge_commit_job.dist.duration", stats[:create_merge_commit_duration], tags: ["duration:create_merge_commit"])
      GitHub.dogstats.distribution("pull_request.create_pull_request_merge_commit_job.dist.duration", stats[:track_multiple_merge_base_prs_duration], tags: ["duration:track_multiple_merge_base_prs"])
      GitHub.dogstats.distribution("pull_request.create_pull_request_merge_commit_job.dist.duration", stats[:total_duration], tags: ["duration:total"])
      GitHub.dogstats.distribution("pull_request.create_pull_request_merge_commit_job.dist.retries", stats[:retries])
    end
  end

  def serialize
    super.merge(first_enqueued_at: first_enqueued_at)
  end

  def deserialize(job_data)
    super
    @first_enqueued_at = job_data["first_enqueued_at"]
  end

  def first_enqueued_at
    if @first_enqueued_at.present?
      DateTime.parse(@first_enqueued_at)
    elsif enqueued_at.present?
      DateTime.parse(enqueued_at.to_s)
    end
  end

  def pull_request
    return @pull_request if defined?(@pull_request)
    pull_id = arguments.first
    @pull_request = PullRequest.find(pull_id)
  end

  def repo
    return @repo if defined?(@repo)
    @repo = pull_request.repository
  end

  # odd name to avoid conflicting with ActiveJob::LockingJob#lock_key
  def commit_lock_key
    # TODO: our association tracker is forcing bad patterns. This is only needed
    # because the job can be enqueued as a side effect of a graphql query which
    # disallows direct association loads, so we do this async dance first to work
    # around it.
    promises = [pull_request.async_repository, pull_request.async_base_user, pull_request.async_head_user]
    key_promise = Promise.all(promises).then do
      base_oid = pull_request.current_base_oid
      head_oid = pull_request.current_head_oid
      "#{pull_request.id}:#{base_oid}:#{head_oid}"
    end
    key_promise.sync
  rescue ActiveRecord::RecordNotFound
    "nil:nil:nil"
  end

  def failbot_context
    {
      repo_id: pull_request.repository_id,
      pull_request_id: pull_request.id,
      base_oid: pull_request.mergeable_base_sha,
      head_oid: pull_request.mergeable_head_sha,
      job_id: job_id,
    }
  end

  def logging_context
    failbot_context.merge(spec: repo&.dgit_spec)
  end

  def with_restraint(repository)
    lock_key =
      if GitHub.flipper[:cprmc_concurrency_per_network].enabled?(repository.network)
        "CreatePullRequestMergeCommit-nw:#{repository.network_id}"
      else
        "CreatePullRequestMergeCommit-#{repository.id}"
      end
    concurrency = GitHub.flipper[:cprmc_half_concurrency].enabled?(repository) ? (MAX_CONCURRENT / 2).to_i : MAX_CONCURRENT
    restraint = GitHub::Restraint.new
    restraint.lock!(lock_key, concurrency, RATE_LIMITER_TTL) do
      yield
    end
  end

  def track_multiple_merge_base_prs(sha)
    return unless sha.present? && GitHub.flipper[:track_multiple_merge_base_prs].enabled?(repo)
    h = pull_request.head_sha
    b = pull_request.current_base_sha
    merge_commit = repo.commits.find(sha)
    if merge_commit.present? && repo.rpc.merge_bases(b, h).many?
      difference = (merge_commit.diff.summary.changed_files - pull_request.comparison.diffs.summary.changed_files).abs
      GitHub.dogstats.increment("pull_request.merge_bases.hidden_file") unless difference == 0
      GitHub.logger.info(
        "gh.job.name": "CreatePullRequestMergeCommitJob",
        "code.function": "track_multiple_merge_base_prs",
        "gh.repo.id": repo.id,
        "gh.pull_request.id": pull_request.id,
        "gh.pull_request.hidden_files_count": difference,
        "gh.pull_request.merge_commit_sha": sha,
        "gh.pull_request.current_base_sha": b,
        "gh.pull_request.head_sha": h
      )
    end
  end
end
