# typed: true
# frozen_string_literal: true

class AutoMergeJob < ApplicationJob
  include GitHub::Memoizer

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

  discard_on(ActiveRecord::RecordNotFound) do |job, error|
    log!(
      pull_request: job.arguments.first,
      outcome: "discarded_record_not_found",
      error: error,
    )
  end

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
    log!(outcome: "exhausted_unknown_merge_state", pull_request:, error:)
    raise error
  end

  COMPARISON_MISMATCH_WAIT = 1.second
  COMPARISON_MISMATCH_RETRIES = 5
  retry_on(Git::Ref::ComparisonMismatch, wait: COMPARISON_MISMATCH_WAIT, jitter: JITTER, attempts: COMPARISON_MISMATCH_RETRIES) do |job, error|
    pull_request = job.arguments.first
    pull_request&.auto_merge_request&.disable(:parent_mismatch)
    log!(outcome: "exhausted_comparison_mismatch", pull_request:, error:)
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
      unless pull_request = T.let(pull_request, T.nilable(PullRequest))
        return
      end

      logger.append_pull_request_context(pull_request)

      if auto_merge_request = T.let(pull_request.auto_merge_request, T.nilable(AutoMergeRequest))
        logger.append({
          id: auto_merge_request.id,
          merge_method: auto_merge_request.merge_method,
          merge_error: auto_merge_request.merge_error,
          repository_id: auto_merge_request.repository_id,
          created_at: auto_merge_request.created_at,
        })
      end

      if user = auto_merge_request&.user
        logger.append({ id: user.id, type: user.class.to_s }, prefix: "gh.actor")
      end

      if pull_request.merged? || pull_request.closed?
        logger.append({ outcome: "skipped_merged_or_closed" })

        return
      end

      unless pull_request.auto_merge_request
        logger.append({ outcome: "skipped_no_auto_merge_request" })

        return
      end

      if actor_ip = auto_merge_request&.actor_ip_address
        Audit.context.push(actor_ip:)
      end

      # Stacked PRs bypass merge state readiness checks — non-bottom PRs target
      # unprotected intermediate branches where merge state may never be "ready."
      if auto_merge_request&.merge_queue_stack? || auto_merge_request&.auto_merge_stack?
        logger.append({
          outcome: "skipped_stacked_pr",
          phase: "job"
        })

        auto_merge_for_stack(pull_request:, user:)
        return
      end

      merge_state = pull_request.cached_merge_state(viewer: user)

      logger.append({
        merge_state: merge_state.status,
        ready_for_auto_merge_job: merge_state.ready_for_auto_merge_job?,
        unfulfilled_protected_branch_policy_reason_codes: merge_state.unfulfilled_protected_branch_policy_reason_codes
      })

      unless merge_state.ready_for_auto_merge_job?
        logger.append({
          outcome: "skipped_merge_state_not_ready",
          phase: "job"
        })
        return
      end

      if merge_state.unknown?
        GitHub.dogstats.increment("pull_request.merge_state_unknown")
        pull_request.enqueue_mergeable_update
        logger.append({
          outcome: "unknown_merge_state",
          phase: "job"
        })
        raise UnknownMergeState, "Merge state is unknown"
      end

      merge_queue = MergeQueue.for(repository: pull_request.repository, branch: pull_request.base_ref)
      if merge_queue
        auto_merge_for_queue(pull_request: pull_request, merge_queue: merge_queue, user: user)
      else
        logger.append({ outcome: "success_invoked_perform_auto_merge" })
        with_write { pull_request.perform_auto_merge }
      end
    end
  ensure
    logger.flush if FeatureFlag.vexi.enabled?(:auto_merge_telemetry, pull_request.repository, default: false)
  end

  private

  sig { returns(PullRequests::Shared::Logger) }
  memoize def logger
    log = PullRequests::Shared::Logger.new(feature: "auto_merge", default_prefix: "gh.pull_request.auto_merge_request")
    log.append({ phase: "job" })
    log
  end

  def auto_merge_for_queue(pull_request:, merge_queue:, user:)
    auto_merge_request = pull_request.auto_merge_request

    unless FeatureFlag.vexi.enabled?(:use_mq_for_auto_merge_if_present, pull_request.repository, default: false)
      if !auto_merge_request.merge_method.in?(%w[merge_queue merge_queue_solo merge_queue_jump])
        GitHub.dogstats.increment("merge_queue.auto_merge_request.unknown_merge_method.#{auto_merge_request.merge_method}")

        err = InvalidMergeMethod.new("#{auto_merge_request.merge_method} merge method is not valid for merge queue")
        Failbot.report(
          err,
          "gh.user.id": user.id,
          "gh.pull_request.id": pull_request.id,
          "gh.pull_request.auto_merge_request.id": auto_merge_request.id,
          "gh.pull_request.auto_merge_request.solo": auto_merge_request.merge_queue_solo?,
          "gh.pull_request.auto_merge_request.jump_queue": auto_merge_request.merge_queue_jump?,
        )

        logger.append({ outcome: "error_invalid_merge_method" })
        logger.append_exception(err)
        raise err
      end
    end

    if merge_queue.has_entry_for?(pull_request: pull_request)
      GitHub.dogstats.increment("merge_queue.auto_merge_request.already_enqueued")
      logger.append({ outcome: "skipped_already_enqueued" })
      return
    end

    with_write do
      merge_queue.enqueue!(
        pull_request: pull_request,
        enqueuer: user,
        solo: auto_merge_request.merge_queue_solo?,
        jump_queue: auto_merge_request.merge_queue_jump?,
      )

      # Destroy the auto-merge request after successfully enqueuing to prevent
      # confusing "auto-merge was automatically disabled" events when retries expire.
      # The PR is now in the merge queue, so the auto-merge request is no longer needed.
      if pull_request.repository&.feature_flag_enabled?(:pull_requests_destroy_auto_merge_after_enqueue, default: false)
        auto_merge_request.destroy
      end
    end

    logger.append({ outcome: "success_enqueued_to_merge_queue" })
  rescue ActiveRecord::RecordInvalid => e
    GitHub.dogstats.increment("merge_queue.auto_merge_request.failure")

    Failbot.report(
      e,
      "gh.user.id": user.id,
      "gh.pull_request.id": pull_request.id,
      "gh.pull_request.auto_merge_request.id": auto_merge_request.id,
      "gh.pull_request.auto_merge_request.solo": auto_merge_request.merge_queue_solo?,
      "gh.pull_request.auto_merge_request.jump_queue": auto_merge_request.merge_queue_jump?,
    )

    logger.append({ outcome: "error_enqueue_failed" })
    logger.append_exception(e)
  end

  def auto_merge_for_stack(pull_request:, user:)
    with_write do
      case result = PullRequests::Stacks::Merging::AddToMergeQueue.new(pull_request:, actor: user).call
      when PullRequests::Stacks::Merging::Result::Success
        # Destroy the auto-merge request after successfully enqueuing to prevent
        # confusing "auto-merge was automatically disabled" events when retries expire.
        # The PRs are now in the merge queue, so the auto-merge request is no longer needed.
        pull_request.auto_merge_request&.destroy
      when PullRequests::Stacks::Merging::Result::Waiting
        # Merging validation failed (e.g. rule suite not passing yet).
        # Exit silently — the auto-merge request stays alive and the job
        # will be re-triggered when conditions change, matching how
        # auto_merge_for_queue swallows RecordInvalid from enqueue!.
        GitHub.dogstats.increment("merge_queue.stacks.enqueue.waiting")

        GitHub.logger.info({
          "gh.pull_requests.auto_merge_request.outcome": "waiting",
          "gh.pull_requests.auto_merge_request.message": result.message,
          "gh.user.id": user.id,
          "gh.pull_request.id": pull_request.id,
        })
      when PullRequests::Stacks::Merging::Result::NoLongerStacked
        # The stack was deleted between the sync and async phases.
        # Destroy the auto-merge request since it targets a stack
        # that no longer exists.
        GitHub.dogstats.increment("merge_queue.stacks.enqueue.no_longer_stacked")

        # TODO: For non-merge queue mode this should have an auto merge dismissal reason.
        pull_request.auto_merge_request&.destroy
      when PullRequests::Stacks::Merging::Result::Error
        GitHub.dogstats.increment("merge_queue.stacks.enqueue.failure")

        GitHub.logger.info({
          "gh.pull_requests.auto_merge_request.outcome": "error",
          "gh.pull_requests.auto_merge_request.message": result.message,
          "gh.user.id": user.id,
          "gh.pull_request.id": pull_request.id,
        })
      end
    end
  end

  sig { params(pull_request: T.nilable(PullRequest), outcome: T.untyped, error: T.untyped).void }
  def self.log!(pull_request:, outcome:, error:)
    logger = PullRequests::Shared::Logger.new(feature: "auto_merge", default_prefix: "gh.pull_request.auto_merge_request")

    if pull_request
      logger.append_pull_request_context(pull_request)

      if repository = pull_request.repository
        logger.append_repository_context(repository)
      end

      if auto_merge_request = pull_request.auto_merge_request
        logger.append({
          id: auto_merge_request.id,
          merge_method: auto_merge_request.merge_method,
          merge_error: auto_merge_request.merge_error,
          repository_id: auto_merge_request.repository_id,
          created_at: auto_merge_request.created_at,
        })
      end

      if user = auto_merge_request&.user
        logger.append({ id: user.id, type: user.class.to_s }, prefix: "gh.actor")
      end
    end

    logger.append({
      outcome: outcome,
      phase: "job",
    })

    logger.append_exception(error) if error

    logger.flush if FeatureFlag.vexi.enabled?(:auto_merge_telemetry, repository, default: false)
  end

  private_class_method :log!
end
