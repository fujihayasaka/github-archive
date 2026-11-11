# typed: true
# frozen_string_literal: true

class ApplySecurityConfigurationToRepositoryJob < ApplicationJob
  use_primaries ApplicationRecord::Notify

  include GitHub::Memoizer
  include SecretScanning::Features::FeatureFlagHelper
  include SecurityProductsEnablement::SecretScanningBackfillHelper

  queue_as :security_configurations

  FANOUT_STAGGER_CONTEXT_KEY = :apply_security_configuration_to_repository_job_fanout_stagger

  # Bulk "apply to all repos" can release thousands of per-repository jobs from a
  # single parent. The context spreads them at a steady rate of BATCH_SIZE per
  # BATCH_INTERVAL (250 / 30s) so the per-repo seat-check RPCs arrive at a pace the
  # turboghas frontend can absorb instead of all at once.
  class FanoutStaggerContext
    BATCH_SIZE = 250
    BATCH_INTERVAL = T.let(30.seconds, ActiveSupport::Duration)

    def initialize
      @enqueued_count = 0
    end

    # Spread enqueues evenly across the window (BATCH_SIZE per BATCH_INTERVAL) rather
    # than releasing BATCH_SIZE jobs at once each interval. Even spacing preserves the
    # same overall release rate while avoiding a fresh thundering herd at every interval
    # boundary.
    def current_wait
      BATCH_INTERVAL * @enqueued_count / BATCH_SIZE
    end

    def increment!
      @enqueued_count += 1
    end
  end

  def self.with_fanout_stagger
    previous_context = Thread.current[FANOUT_STAGGER_CONTEXT_KEY]
    Thread.current[FANOUT_STAGGER_CONTEXT_KEY] = FanoutStaggerContext.new

    yield
  ensure
    Thread.current[FANOUT_STAGGER_CONTEXT_KEY] = previous_context
  end

  before_enqueue do |job|
    stagger_context = Thread.current[FANOUT_STAGGER_CONTEXT_KEY]
    next unless stagger_context

    enqueue_wait = stagger_context.current_wait
    job.scheduled_at = enqueue_wait.from_now if enqueue_wait.to_i.positive?

    stagger_context.increment!
  end

  retry_on_dirty_exit
  # Spread retries across the polynomial wait window. With 1k+ siblings fanned out from
  # OrganizationSecurityConfigurationJob the deterministic 3s / 18s / 83s / 258s schedule
  # otherwise reproduces the original storm on every retry tier.
  retry_on_recoverable_exceptions(jitter: 0.15)

  # Error classes for precondition / retry semantics live on the domain
  # attacher. We re-expose them here as aliases so that external callers and
  # the job's own retry_on/discard_on macros can keep referencing them via
  # this constant namespace.
  Attacher = SecurityProductsEnablement::ConfigurationAttacher
  Error = Attacher::Error
  RetryableError = Attacher::RetryableError
  FatalError = Attacher::FatalError
  RepositoryNotFound = Attacher::RepositoryNotFound
  OwnerNotFound = Attacher::OwnerNotFound
  ActorNotFound = Attacher::ActorNotFound
  SecurityConfigurationNotFound = Attacher::SecurityConfigurationNotFound
  RepositorySecurityConfigurationNotFound = Attacher::RepositorySecurityConfigurationNotFound
  SecurityConfigurationOwnerMismatch = Attacher::SecurityConfigurationOwnerMismatch
  RepositoryDeleted = Attacher::RepositoryDeleted
  OwnerDeleted = Attacher::OwnerDeleted

  # For cases where we can reasonably expect a different result when retrying
  # (i.e. possible DB lag).
  EXCEPTIONS = [RetryableError, AdvancedSecurityLicense::TurboghasError, CodeScanning::AutoCodeqlError, Actions::ServiceError, Actions::RunnerScaleSet::RunnerScaleSetServiceError]
  retry_on *T.unsafe(EXCEPTIONS), wait: :polynomially_longer, attempts: 5 do |job, error|
    job.handle_permanent_job_failure(error)
    raise error
  end

  # For cases where we don't expect a retry to result in a different result,
  # discard so that we mark the job as failed.
  discard_on FatalError

  before_enqueue do |job|
    next if job.applying_to_new_repo?
    next if job.executions != 0 # Skip this logic if we're enqueueing due to a retry:

    self.class.update_types(security_configuration).each { |update_type| repo_counter&.increment(update_type) }
  end

  after_perform :mark_job_as_completed

  around_perform do |_job, block|
    GitHub.context.push(actor:) do
      Audit.context.push(actor:) do
        block.call
      end
    end
  end

  def handle_permanent_job_failure(error)
    mark_job_as_completed
    mark_repository_security_configuration_as_failed(error)
  end

  def mark_job_as_completed
    # If the reason this job was enqueued was repo creation, we can skip progress updates:
    return if applying_to_new_repo?

    self.class.update_types(security_configuration).each { |update_type| repo_counter&.decrement(update_type) }

    update_job_progress_tracker
  end

  def mark_repository_security_configuration_as_failed(error)
    reason = T.must(error.class.name).demodulize.underscore

    RepositorySecurityConfiguration.throttle_writes_with_retry do
      repository_security_configuration&.update!(state: :failed, failure_reason: reason) if repository_security_configuration&.attaching?
    end
  end

  after_discard do |job, error|
    job.handle_permanent_job_failure(error)
  end

  sig do
    params(
      actor_id: Integer,
      repository_id: Integer,
      security_configuration_id: Integer,
      override_params: T::Hash[Symbol, String],
      reason: T.nilable(Symbol), # Valid values: :repo_creation, :repo_transfer, :repo_visibility_change, :repo_unarchived
      prevent_additional_sku_usage: T.nilable(T::Array[GitHub::Turboghas::SKU]),
      attachment_id: T.nilable(Integer),
    ).void
  end
  def perform(
    actor_id:,
    repository_id:,
    security_configuration_id:,
    override_params: {},
    reason: nil,
    prevent_additional_sku_usage: nil,
    attachment_id: nil
  )
    GitHub.logger.info("Beginning job")

    SecurityProductsEnablement.domain.configurations.attach_to_repository(
      actor_id:,
      repository_id:,
      security_configuration_id:,
      service_manager_overrides: override_params,
      reason:,
      disallowed_skus: prevent_additional_sku_usage,
      attachment_id:,
      # Preserve existing dashboards/alerts that key off the legacy job namespace.
      instrumentation_namespace: "apply_security_configuration_to_repository_job",
    )
  rescue ActiveRecord::RecordNotFound => e
    # sometimes the repository is deleted during the middle of our job run
    # this checks for that exception and raises a RepositoryDeleted exception to discard the job
    raise(repository_deleted? ? RepositoryDeleted : e)
  end


  sig { returns(T::Hash[Symbol, T.untyped]) }
  def logging_context
    # note we can't use repository_owner in this method as it will raise if the repository has been soft deleted
    owner = repository&.owner
    owner_tag_prefix = owner&.organization? ? "gh.org" : "gh.user"

    tags = {
      "gh.repo.id": arguments.dig(0, :repository_id),
      "gh.repo.name": repository&.name,
      "#{owner_tag_prefix}.id": repository&.owner_id,
      "#{owner_tag_prefix}.login": owner&.display_login,
      "gh.enduser.id": arguments.dig(0, :actor_id),
      "gh.enduser.login": actor&.display_login,
      "gh.security_configuration.id": arguments.dig(0, :security_configuration_id),
      "gh.security_configuration.apply_repo_job.override_params": arguments.dig(0, :override_params),
      "gh.security_configuration.apply_repo_job.reason": arguments.dig(0, :reason),
      "gh.security_configuration.apply_repo_job.prevent_additional_sku_usage": arguments.dig(0, :prevent_additional_sku_usage),
      "code.namespace": self.class.name,
    }

    super.merge(tags)
  end

  sig { returns(T.nilable(::Repository)) }
  memoize def repository
    repository_id = arguments.dig(0, :repository_id)
    return unless repository_id
    Repositories::Public.find_active(repository_id)
  end

  sig { returns(User) }
  memoize def repository_owner
    repository&.owner or raise OwnerNotFound, "Repository Owner not found."
  end

  sig { returns(T.nilable(T::Boolean)) }
  def repository_deleted?
    repository_id = arguments.dig(0, :repository_id)
    return unless repository_id
    Repositories::Public.is_deleted?(repository_id)
  end

  sig { returns(T.nilable(User)) }
  memoize def actor
    actor_id = arguments.dig(0, :actor_id)
    return unless actor_id
    User.find_by(id: actor_id)
  end

  sig { returns(T.nilable(SecurityConfiguration)) }
  memoize def security_configuration
    security_configuration_id = arguments.dig(0, :security_configuration_id)
    return unless security_configuration_id
    SecurityConfiguration.find_by(id: security_configuration_id)
  end

  sig { returns(T.nilable(RepositorySecurityConfiguration)) }
  memoize def repository_security_configuration
    return unless repository.present? && security_configuration.present?
    RepositorySecurityConfiguration.find_by(
      repository_id: T.must(repository).id,
      security_configuration_id: T.must(security_configuration).id
    )
  end

  sig { void }
  def update_job_progress_tracker
    return unless repository_owner.organization?

    job_progress_tracker.decrement_jobs
  rescue OwnerNotFound
    # if a repository is soft deleted this can be triggered
    # we don't actually care so lets swallow the exception and return
  end

  sig { returns(SecurityProductsEnablement::JobProgressTracker) }
  memoize def job_progress_tracker
    business_id = repository_owner.business&.id
    tracker = SecurityProductsEnablement::JobProgressTracker.new(repository_owner.id, business_id:)

    if security_configuration && arguments.dig(0, :override_params, :skip_backfill_request).present?
      tracker.on_finish do |repository_ids|
        publish_secret_scanning_backfill(
          security_configuration: T.must(security_configuration),
          owner: repository_owner,
          repository_ids:
        )
      end
    end

    tracker
  end

  sig { returns(T.nilable(BlockedSettings::RepoCounter)) }
  memoize def repo_counter
    return nil unless repository
    BlockedSettings.new(repository_owner).repo_counter
  end

  sig { returns(T::Boolean) }
  memoize def applying_to_new_repo?
    arguments.dig(0, :reason) == :repo_creation || arguments.dig(0, :reason) == :repo_transfer
  end

  # Returns an array of symbols, each one mapping to a GHAS feature.
  # The symbols represent the update_type that will be incremented/decremented in the repo_counter of BlockedSettings
  sig { params(security_configuration: T.nilable(SecurityConfiguration)).returns(T::Array[Symbol]) }
  def self.update_types(security_configuration)
    return [] unless security_configuration

    update_types = [T.must(security_configuration).enable_ghas ? :advanced_security_enable_all : :advanced_security_disable_all]
    update_types + [
      [:code_scanning, :auto_codeql_enable_all, :auto_codeql_disable_all],
      [:secret_scanning, :secret_scanning_enable_all, :secret_scanning_disable_all],
      [:secret_scanning_validity_checks, :secret_scanning_validity_checks_enable_all, :secret_scanning_validity_checks_disable_all],
      [:secret_scanning_push_protection, :secret_scanning_push_protection_enable_all, :secret_scanning_push_protection_disable_all]
    ].map do |feature, enable_type, disable_type|
      security_configuration.send("#{feature}_enabled?") ? enable_type : disable_type
    end
  end
end
