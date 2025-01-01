# typed: true
# frozen_string_literal: true

class AutoMergeJob < ApplicationJob
  class UnknownMergeState < StandardError ; end
  class InvalidMergeMethod < StandardError ; end

  use_replicas ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::RepositoriesActionsChecks,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::Spokes,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Permissions,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Notify,
    allow_replication_lag: [
      ApplicationRecord::Iam
    ]

  queue_as :auto_merge
  retry_on_dirty_exit

  discard_on ActiveRecord::RecordNotFound

  MAX_ATTEMPTS = 20
  RETRY_WAIT = 10.seconds
  # wait up to an additional RETRY_WAIT * JITTER seconds per retry
  JITTER = 0.5
  MAX_CONCURRENT_JOBS = 1
  LOCK_TTL = 30.seconds

  retry_on(SpokesAPI::ResourceExhausted, wait: :polynomially_longer)
  retry_on(GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: MAX_ATTEMPTS)
  retry_on(AutoMergeJob::UnknownMergeState, wait: RETRY_WAIT, jitter: JITTER, attempts: MAX_ATTEMPTS) do |job, error|
    pull_request = job.arguments.first
    pull_request&.auto_merge_request&.disable(:not_mergeable)

    raise error
  end

  COMPARISON_MISMATCH_WAIT = 1.second
  COMPARISON_MISMATCH_RETRIES = 5
  retry_on(Git::Ref::ComparisonMismatch, wait: COMPARISON_MISMATCH_WAIT, jitter: JITTER, attempts: COMPARISON_MISMATCH_RETRIES) do |job, error|
    pull_request = job.arguments.first
    pull_request&.auto_merge_request&.disable(:parent_mismatch)

    raise error
  end

  resolve_tenant_context do |pull_request|
    repository = pull_request.repository
    if repository
      Business.find_by(id: repository.tenant_id)
    end
  end

  def restraint_lock_key(pull_request)
    "auto_merge_job_#{pull_request.id}"
  end

  def perform(pull_request)
    restraint = GitHub::Restraint.new
    restraint.lock!(restraint_lock_key(pull_request), MAX_CONCURRENT_JOBS, LOCK_TTL) do
      return if pull_request.merged? || pull_request.closed?
      return unless pull_request.auto_merge_request
      if actor_ip = pull_request.auto_merge_request.actor_ip_address
        Audit.context.push(actor_ip:)
      end

      user = pull_request.auto_merge_request.user
      merge_state = pull_request.cached_merge_state(viewer: user)

      unless merge_state.ready_for_auto_merge_job?
        GitHub.dogstats.increment("pull_request.auto_merge_job.not_ready_for_auto_merge_job", tags: ["merge_state:#{merge_state.status}"])
        if merge_state.behind? && FeatureFlag.vexi.enabled?(:raise_on_not_ready_for_auto_merge, pull_request.repository, default: false)
          raise UnknownMergeState, "Merge state is behind"
        end
        return
      end

      if merge_state.unknown?
        GitHub.dogstats.increment("pull_request.merge_state_unknown")
        pull_request.enqueue_mergeable_update
        raise UnknownMergeState, "Merge state is unknown"
      end

      merge_queue = MergeQueue.for(repository: pull_request.repository, branch: pull_request.base_ref)
      if merge_queue
        auto_merge_for_queue(pull_request: pull_request, merge_queue: merge_queue, user: user)
      else
        with_write { pull_request.perform_auto_merge }
      end
    end
  end

  private

  def auto_merge_for_queue(pull_request:, merge_queue:, user:)
    auto_merge_request = pull_request.auto_merge_request

    if merge_queue.has_entry_for?(pull_request: pull_request)
      GitHub.dogstats.increment("merge_queue.auto_merge_request.already_enqueued")
      return
    end

    with_write do
      merge_queue.enqueue!(
        pull_request: pull_request,
        enqueuer: user,
        solo: auto_merge_request.merge_queue_solo?,
        jump_queue: auto_merge_request.merge_queue_jump?,
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    GitHub.dogstats.increment("merge_queue.auto_merge_request.failure")

    Failbot.report(
      e,
      "gh.user.id": user.id,
      "gh.pull_request.id": pull_request.id,
      "gh.auto_merge_request.id": auto_merge_request.id,
      "gh.auto_merge_request.solo": auto_merge_request.merge_queue_solo?,
      "gh.auto_merge_request.jump_queue": auto_merge_request.merge_queue_jump?,
    )
  end
end
