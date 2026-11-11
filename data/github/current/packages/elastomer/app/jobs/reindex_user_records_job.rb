# typed: true
# frozen_string_literal: true

class ReindexUserRecordsJob < ApplicationJob
  queue_as :index_bulk
  retry_on_dirty_exit

  retry_on Redis::BaseError, wait: :exponentially_longer, attempts: 5

  DATETIME_FORMAT = "%Y-%m-%d %H:%M (UTC)"

  JOB_CONFIGS = {
    issues_created: {
      class: RepairIssuesIndexJob,
      index_name: "issues",
      target_scope: :user_created,
      slug: "Issues this user created",
      elastomer: true,
    },
    issues_commented: {
      class: RepairIssuesIndexJob,
      index_name: "issues",
      target_scope: :user_commented,
      slug: "Issues this user commented on",
      elastomer: true,
    },
    pull_requests_created: {
      class: RepairPullRequestsIndexJob,
      index_name: "pull-requests",
      target_scope: :user_created,
      slug: "Pull requests this user created",
      elastomer: true,
    },
    pull_requests_reviewed: {
      class: RepairPullRequestsIndexJob,
      index_name: "pull-requests",
      target_scope: :user_reviewed,
      slug: "Pull requests this user reviewed",
      elastomer: true,
    },
    pull_requests_commented: {
      class: RepairPullRequestsIndexJob,
      index_name: "pull-requests",
      target_scope: :user_commented,
      slug: "Pull requests this user commented on",
      elastomer: true,
    },
    repositories: {
      class: RepairReposIndexJob,
      index_name: "repos",
      target_scope: :user,
      slug: "Repositories this user owns",
      elastomer: true,
    },
    releases: {
      class: RepairReleasesIndexJob,
      index_name: "releases",
      target_scope: :user,
      slug: "Releases authored by this user",
      elastomer: true,
    },
    commits: {
      class: RepairCommitsIndexJob,
      index_name: "commits",
      target_scope: :user,
      slug: "Commits authored by this user",
      elastomer: true,
    },
    gists: {
      class: RepairGistsIndexJob,
      index_name: "gists",
      target_scope: :user,
      slug: "Gists authored by this user",
      elastomer: true,
    },
    wikis: {
      class: RepairWikisIndexJob,
      index_name: "wikis",
      target_scope: :user,
      slug: "Wikis for repositories owned by this user",
      elastomer: true,
    },
    workflow_runs: {
      class: RepairWorkflowRunsIndexJob,
      index_name: "workflow-runs",
      target_scope: :actor,
      slug: "Workflow runs triggered by this user",
      elastomer: true,
    },
    code: {
      class: BlackbirdOnboardJob,
      index_name: "code",
      # Job expects an array of user ids to onboard, so proc_args returns an array of this array
      # so that positional args are passed correctly.
      proc_args: ->(user_id) { [[User.find(user_id)]] },
      slug: "Code authored by this user",
      elastomer: false, # This is a special case that doesn't use the normal RepairJob interface
    }
  }

  # Controls how long after starting the job that worker counts
  # can be adjusted for sub-jobs. This allows the system to stabilize and
  # for smaller sub-jobs to succeed before anyone starts throwing more resources
  # at the orchestration.
  WORKER_ADJUSTMENT_DELAY = 10.minutes

  class Stats
    include StatusHelper

    sig { returns(T.nilable(Symbol)) }
    attr_accessor :last_action

    sig { returns(T.nilable(String)) }
    attr_accessor :started_at, :completed_at, :last_action_at, :eta

    sig { returns(T.nilable(Time)) }
    attr_accessor :started_at_time

    sig { returns(Float) }
    attr_accessor :elapsed, :overall_completion_percentage

    sig { returns(T::Array[Hash]) }
    attr_accessor :jobs

    def active?
      last_action && [:start, :resume, :update_workers].include?(last_action)
    end

    def paused?
      last_action == :pause
    end

    def complete?
      completed_at.present?
    end

    def worker_adjustment_available?
      return false unless started_at_time
      (Time.now - T.must(started_at_time)) >= ReindexUserRecordsJob::WORKER_ADJUSTMENT_DELAY
    end

    sig { returns(String) }
    def readable_elapsed
      precise_duration(elapsed)
    end
  end

  class RedisInterface
    BASE = "search.repair.reindex_user_records_job"
    attr_reader :user_id

    def initialize(user_id)
      @user_id = user_id
    end

    def job_key
      "#{BASE}.#{user_id}"
    end

    def facet_key(facet)
      "#{job_key}.#{facet}"
    end

    def redis
      Search::JobCoordination.redis
    end

    def set(key, value)
      redis.hset(job_key, key, value)
    end

    def get(key)
      redis.hget(job_key, key)
    end

    def clear!
      redis.del(job_key)
    end
  end

  def perform(user_id, action, requeue: false, **opts)
    redis = RedisInterface.new(user_id)
    error = nil
    if [:start, :pause, :resume, :reset, :update_workers].include?(action)
      redis.set("last_action", action.to_s)
      redis.set("last_action_at", Time.current.utc.strftime(DATETIME_FORMAT))
    end

    if action == :pause
      pause_all_jobs_for_user!(user_id)
      requeue = false
      return
    elsif action == :reset
      reset_all_jobs_for_user!(user_id)
      requeue = false
      redis.clear!
      return
    end

    return unless self.class.enabled_for_user?(user_id)

    if [:start, :resume, :update_workers].include?(action)
      start_options = {
        workers: opts.fetch(:workers, {}),
      }
      requeue = true unless action == :update_workers
      if action == :start
        redis.set("started_at", Time.current.to_s)
        reset_all_jobs_for_user!(user_id)
        Search.add_to_search_index("user", user_id)
      end
      start_all_jobs_for_user!(user_id, start_options)
      action = :check_for_completion
    end

    if action == :check_for_completion
      action = :complete if check_for_completion(user_id)
      requeue = false if %w[pause reset].include?(redis.get("last_action")) # Don't requeue if the job was paused while we were working
    end

    if action == :complete
      requeue = false
      redis.set("last_action", "complete")
      redis.set("last_action_at", Time.current.utc.strftime(DATETIME_FORMAT))
      redis.set("completed_at", Time.current.to_s)
    end

    if requeue
      wait = action == :check_for_completion ? 30.seconds : 0
      self.class.set(wait:).perform_later(user_id, action, requeue:, **opts)
    end
  rescue => e
    error = e
    raise
  ensure
    log_perform(user_id, action, requeue, error)
  end

  private

  def log_perform(user_id, action, requeue, error)
    error_class = error.class.name if error
    job_name = self.class.name&.underscore || "unknown"
    message = "#{job_name} performed action #{action} for user_id #{user_id}"
    tags = ["action:#{action}", "search:repair", "job:#{job_name}"]
    if error
      Failbot.report(error)
      message += " with error #{error_class}: #{error.message}"
      tags << "error:#{error_class}"
    end
    GitHub.dogstats.event(
      "ReindexUserRecordsJob performed",
      message,
      tags:,
    )
  end

  public

  def reset_all_jobs_for_user!(user_id)
    JOB_CONFIGS.each do |facet, config|
      next unless config[:elastomer]
      job = self.class.repair_job_for_facet(user_id, facet)
      job.reset!
      job.enable
    end
  end

  def pause_all_jobs_for_user!(user_id)
    JOB_CONFIGS.each do |facet, config|
      next unless config[:elastomer]
      job = self.class.repair_job_for_facet(user_id, facet)
      job.pause
    end
  end

  def start_all_jobs_for_user!(user_id, options = {})
    JOB_CONFIGS.each do |facet, config|
      if config[:elastomer]
        workers = options[:workers] || {}
        raw_worker_count = workers[facet] || workers[facet.to_s]
        worker_count = begin
          raw_worker_count.nil? ? 1 : Integer(raw_worker_count)
        rescue ArgumentError, TypeError
          1
        end
        job = self.class.repair_job_for_facet(user_id, facet)
        job.enable if job.paused?
        job.start(worker_count) if job.enabled?
      else
        # For non-elastomer jobs like BlackbirdOnboardJob, perform directly
        args = config[:proc_args].call(user_id)
        config[:class].perform_later(*args)
      end
    end
  end

  sig { params(user_id: Integer).returns(T::Boolean) }
  def check_for_completion(user_id)
    completed_count = 0
    JOB_CONFIGS.each do |facet, config|
      if config[:elastomer]
        job = self.class.repair_job_for_facet(user_id, facet)
        progress = job.progress
        completed_count += 1 if progress >= 100
      else
        # Non-elastomer jobs like BlackbirdOnboardJob don't track progress
        # Consider them complete immediately (they run async)
        completed_count += 1
      end
    end
    completed_count >= JOB_CONFIGS.size
  end

  sig { params(user_id: T.anything, facet: Symbol).returns(Elastomer::RepairJob) }
  def self.repair_job_for_facet(user_id, facet)
    config = JOB_CONFIGS[facet]
    config[:class].new(config[:index_name], {
      target_scope_id: user_id,
      target_scope: config[:target_scope],
      upsert_only: true,
    })
  end

  def self.enabled_for_user?(user_or_id)
    user = user_or_id.is_a?(User) ? user_or_id : User.find(user_or_id)

    FeatureFlag.vexi.enabled?(:reindex_user_records_job, user, default: false)
  end

  sig { params(user_id: Integer).returns(Stats) }
  def self.stats(user_id)
    redis = RedisInterface.new(user_id)
    started_at = redis.get("started_at")
    completed_at = redis.get("completed_at")
    elapsed = if started_at && completed_at
      Time.parse(completed_at) - Time.parse(started_at)
    elsif started_at
      Time.current - Time.parse(started_at)
    end
    jobs = JOB_CONFIGS.map do |facet, config|
      if config[:elastomer]
        job = repair_job_for_facet(user_id, facet)
        {
          facet: facet,
          slug: config[:slug],
          progress: job.progress.round(2),
          eta: job.estimated_completion_time&.utc&.strftime(DATETIME_FORMAT),
          workers: job.workers,
        }
      else
        {
          facet: facet,
          slug: config[:slug],
          workers: 1,
        }
      end
    end
    completion = jobs.sum { |job| job[:progress] || 100 } / JOB_CONFIGS.size.to_f
    completion = completion.clamp(0, 100)

    Stats.new.tap do |stats|
      stats.last_action = redis.get("last_action")&.to_sym
      stats.last_action_at = redis.get("last_action_at")
      stats.started_at = started_at ? Time.parse(started_at).utc.strftime(DATETIME_FORMAT) : nil
      stats.started_at_time = started_at ? Time.parse(started_at) : nil
      stats.completed_at = completed_at ? Time.parse(completed_at).utc.strftime(DATETIME_FORMAT) : nil
      stats.elapsed = elapsed || 0.0
      stats.jobs = jobs
      stats.overall_completion_percentage = completion
      stats.eta = jobs.map { |job| job[:eta] }.compact.max
    end
  end
end
