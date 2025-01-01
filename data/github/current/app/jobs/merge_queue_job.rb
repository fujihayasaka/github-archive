# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# Updates a given merge queue based on its current state, e.g. by merging
# entries or ejecting entries from the queue.
#
# Don't call this job directly: use `MergeQueues.execute!` instead.
class MergeQueueJob < ApplicationJob

  include ActiveJob::InitiallyEnqueuedAt

  queue_as :merge_queue

  discard_on ActiveJob::DeserializationError

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  retry_on GitHub::Restraint::UnableToLock, wait: 30.seconds, attempts: 20

  locked_by timeout: 5.minutes, key: ->(job) {
    repository, branch = job.arguments
    "merge-queue-#{repository&.id}-#{branch}"
  }

  resolve_tenant_context do |repository|
    tenant_for_repository(repository)
  end

  sig { params(repository: Repository, branch: String).void }
  def perform(repository, branch)
    ensure_correct_tenant!(repository)

    # Soft-deleted repositories should never run.
    unless repository.active?
      return noop("inactive_repository")
    end

    # Allows disabling of the merge queue job in emergency situations.
    if repository.feature_enabled?(:merge_queue_emergency_shut_off)
      return noop("merge_queue_emergency_shut_off")
    end

    begin
      result = T.let(
        with_write { MergeQueues::Service::Tick.new(repository, branch).call },
        MergeQueues::DecisionEngine::Result
      )
    ensure
      # If we hit an exception, treat it like a waiting result and
      # retry the job after a delay.
      if result.nil?
        result = MergeQueues::DecisionEngine::Result::Waiting
      end

      case result
      when MergeQueues::DecisionEngine::Result::Restart
        MergeQueues.execute!(repository, branch)
      when MergeQueues::DecisionEngine::Result::Waiting
        MergeQueues.delayed_execute!(repository, branch)
      when MergeQueues::DecisionEngine::Result::Done
        # No-op: we're done!
      when MergeQueues::DecisionEngine::Result::Disabled
        MergeQueueDisableJob.perform_later(repository)
      else
        T.absurd(result)
      end

      # Current best practices is to unset/remove the tenant after the process
      # we don't leave behind any context in the thread.
      GitHub::CurrentTenant.remove
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def logging_context
    repo, branch = arguments

    super.merge({
      repository: repo.nwo,
      branch:,
    })
  end

  sig { params(reason: String).void }
  def noop(reason)
    repo, branch = arguments

    GitHub.logger.info(
      "noop",
      "gh.merge_queue.noop_reason": reason,
      "gh.repo.id": repo.id,
      "gh.merge_queue.branch": branch,
    )
  end

  # This job may not always be invoked from a HTTP req/res cycle. Ensure that the
  # tenant is correctly set as ActiveRecord relations will not load correctly when
  # the default Proxima scopes are applied.
  sig { params(repository: Repository).void }
  def ensure_correct_tenant!(repository)
    return unless GitHub.multi_tenant_enterprise?

    current_tenant = GitHub::CurrentTenant.get
    required_tenant = MergeQueueJob.tenant_for_repository(repository)

    if current_tenant != required_tenant
      GitHub::CurrentTenant.set(required_tenant)
    end
  end

  sig { params(repository: Repository).returns(T.nilable(Business)) }
  def self.tenant_for_repository(repository)
    GitHub::CurrentTenant.unscope do
      Business.find_by(id: repository.tenant_id)
    end
  end
end
