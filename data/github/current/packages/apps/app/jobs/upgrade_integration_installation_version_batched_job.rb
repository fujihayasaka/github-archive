# typed: true
# frozen_string_literal: true

# Processes installations for a single outdated version in batches,
# upgrading each installation to the target version.
#
# Enqueued by UpgradeIntegrationInstallationVersionOrchestrationJob —
# one instance per outdated version number.
class UpgradeIntegrationInstallationVersionBatchedJob < BatchedJob
  include GitHub::Memoizer

  BATCH_SIZE = 100
  LOCK_TIMEOUT = 2.minutes

  queue_as :upgrade_integration_installation_version
  exempt_from_tenant_context_requirement
  retry_on_dirty_exit
  retry_on_recoverable_exceptions(attempts: 10)

  # Prevent duplicate jobs for the same (integration, target_version, outdated_version).
  # offset_item_id is intentionally excluded — it is a batch cursor that changes on
  # every continuation re-enqueue; including it would give each batch a unique key
  # and defeat the purpose of the lock.
  locked_by timeout: LOCK_TIMEOUT, key: ->(job) {
    kwargs = job.arguments.first
    unless kwargs.is_a?(Hash)
      raise ArgumentError, "UpgradeIntegrationInstallationVersionBatchedJob expects first argument to be a Hash, got #{kwargs.class}"
    end
    integration_id          = kwargs.fetch(:integration_id)
    target_version_number   = kwargs.fetch(:target_version_number)
    outdated_version_number = kwargs.fetch(:outdated_version_number)
    "upgrade-installation-version:#{integration_id}:#{target_version_number}:#{outdated_version_number}"
  }

  # Override LockingJob#acquire_lock to be resilient to Redis outages.
  #
  # The default `around_enqueue` callback silently drops the job when `acquire_lock`
  # raises (e.g. Redis::CannotConnectError). For this job that would mean an
  # integration version upgrade is silently abandoned. Instead, we rescue and
  # return `true` so the job is enqueued without a lock. The worst case is two
  # concurrent jobs processing the same upgrade stream — the work is idempotent
  # so this is safe.
  def acquire_lock
    super
  rescue Redis::BaseError
    GitHub.dogstats.increment(
      "job.upgrade_integration_installation_version_batched_job.lock_acquire_redis_error",
      tags: ["phase:enqueue"],
    )
    true
  end

  # Query the next page of installations that are still on the outdated version.
  sig do
    params(
      args: T.untyped,
      integration_id: Integer,
      outdated_version_number: Integer,
      offset_item_id: Integer,
      popular: T::Boolean,
      options: T.untyped
    ).returns(T::Array[IntegrationInstallation])
  end
  def next_batch(*args, integration_id:, outdated_version_number:, offset_item_id: 0, popular: false, **options)
    if use_index_hint?
      integration
        .installations
        .where(integration_version_number: outdated_version_number)
        .where("integration_installations.id > ?", offset_item_id)
        .includes(:target)
        .optimizer_hints("INDEX(integration_installations index_on_integration_id_and_version_number)")
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a
    else
      integration
        .installations
        .where(integration_version_number: outdated_version_number)
        .where("integration_installations.id > ?", offset_item_id)
        .includes(:target)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a
    end
  end

  # Upgrade each installation in the batch to the target version.
  sig do
    params(
      batch: T::Array[IntegrationInstallation],
      args: T.untyped,
      integration_id: Integer,
      target_version_number: Integer,
      updating_actor_id: T.nilable(Integer),
      popular: T::Boolean,
      options: T.untyped
    ).void
  end
  def process_batch(batch, *args, integration_id:, target_version_number:, updating_actor_id: nil, popular: false, **options)
    @finish_reason = :completed

    if newer_version_published?
      @finish_reason = :stale
      emit_count("drop_older_version")
      return
    end

    emit_batch_throughput_metrics(batch.size) do
      batch.each do |installation|
        IntegrationInstallation.throttle_with_retry do
          ApplicationRecord::Permissions.throttle_with_retry do
            IntegrationInstallation::VersionUpgrade.call(
              installation: installation,
              integration: integration,
              target_version: current_target_version,
              updating_actor_id: updating_actor_id,
              popular: popular,
            )
          end
        end
      end
    end
  end

  # Determines whether there are more batches to process.
  sig do
    override
      .params(batch: T::Array[IntegrationInstallation], integration_id: Integer, target_version_number: Integer, popular: T::Boolean, options: T.untyped)
      .returns(T::Boolean)
  end
  def has_next_batch?(batch, integration_id:, target_version_number:, popular: false, **options)
    return false if batch.size < BATCH_SIZE

    if newer_version_published?
      @finish_reason = :stale
      return false
    end

    if cancel_upgrade?
      @finish_reason = :cancelled
      emit_count("cancelled")
      return false
    end

    true
  end

  sig { override.params(finished_successfully: T::Boolean, options: T.untyped).returns(T.untyped) }
  def ensure_perform(finished_successfully:, **options)
    return unless finished_successfully

    reason = @finish_reason || :completed
    emit_count_with_tags("outdated_version_processing_finished", ["reason:#{reason}"])
  end

  # Clear the hash lock before BatchedJob enqueues the next batch continuation.
  # Without this, the continuation enqueue would be blocked by the current lock.
  #
  # Retries at a fixed interval on Redis failures. The lock TTL is controlled by
  # LOCK_TIMEOUT (see locked_by timeout: LOCK_TIMEOUT), so we keep retrying until
  # that window elapses — at which point the lock has expired anyway and the
  # continuation can proceed.
  sig { override.params(args: T.untyped, options: T.untyped).returns(T.untyped) }
  def finalize_batch(*args, **options)
    clear_lock_with_redis_retry
  end

  private

  CLEAR_LOCK_RETRY_INTERVAL_SECONDS = 5

  def clear_lock_with_redis_retry
    lock_expiry_deadline = Time.now + LOCK_TIMEOUT
    begin
      clear_lock
    rescue *GitHub::Config::Redis::REDIS_DOWN_EXCEPTIONS
      if Time.now < lock_expiry_deadline
        emit_count("clear_lock_retry")
        Kernel.sleep(CLEAR_LOCK_RETRY_INTERVAL_SECONDS)
        retry
      end
      # Lock TTL has expired — no need to clear, continuation can proceed.
      emit_count("clear_lock_expired")
    end
  end

  sig { returns(Integration) }
  memoize def integration
    Integration.find_by!(id: arguments.dig(0, :integration_id))
  end

  sig { returns(Integer) }
  memoize def target_version_number
    arguments.dig(0, :target_version_number)
  end

  sig { returns(T::Boolean) }
  memoize def popular
    arguments.dig(0, :popular) || false
  end

  def newer_version_published?
    !target_version_still_latest?
  end

  # Returns true when the target version is still the latest version of the integration.
  # Tries the replica first to reduce load on primary; falls back to primary to guard
  # against false negatives caused by replication lag.
  def target_version_still_latest?
    current_target_version.present?
  end

  memoize def current_target_version
    target_version_matching_latest_on(role: :reading) || target_version_matching_latest_on(role: :writing)
  end

  def target_version_matching_latest_on(role:)
    latest = current_latest_integration_version(role: role)
    latest if latest&.number == target_version_number
  end

  def current_latest_integration_version(role:)
    ActiveRecord::Base.connected_to(role: role) do
      integration.versions.reorder(id: :desc).first
    end
  end

  def cancel_upgrade?
    FeatureFlag.vexi.enabled?(:cancel_upgrade_integration_installation_version_job, integration, default: false)
  end

  def use_index_hint?
    FeatureFlag.vexi.enabled?(:upgrade_installation_version_job_use_index_hint, integration, default: false)
  end

  def emit_batch_throughput_metrics(updated_installation_count)
    started_at = GitHub::Dogstats.monotonic_time
    yield
    elapsed_ms = [0.001, GitHub::Dogstats.duration(started_at)].max
    throughput_per_second = (updated_installation_count / (elapsed_ms / 1000.0)).to_i
    emit_distribution("updated_installations", updated_installation_count)
    emit_distribution("installations_per_second", throughput_per_second)
  end

  def emit_distribution(suffix, value)
    GitHub.dogstats.distribution(
      "job.upgrade_integration_installation_version_batched_job.#{suffix}",
      value,
      tags: tags_for_integration,
    )
  end

  def emit_count(suffix)
    GitHub.dogstats.count(
      "job.upgrade_integration_installation_version_batched_job.#{suffix}",
      1,
      tags: tags_for_integration,
    )
  end

  def emit_count_with_tags(suffix, extra_tags)
    GitHub.dogstats.count(
      "job.upgrade_integration_installation_version_batched_job.#{suffix}",
      1,
      tags: tags_for_integration + extra_tags,
    )
  end

  memoize def tags_for_integration
    tags = ["popular:#{popular}"]
    tags << "integration:#{integration.slug}" if popular
    tags
  end
end
