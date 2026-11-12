# typed: true
# frozen_string_literal: true

# Public: This job will remove all Integrations without a corresponding owner in the database. Does not remove
# Integrations whose Business owner has been soft-deleted.
#
# Built on BatchedJob: each run scans a bounded outer window of Integration records (BATCH_SIZE) starting after the
# given Integration ID cursor, loading records in smaller inner chunks (SCAN_BATCH_SIZE) to keep memory and
# owner-lookup queries bounded. Whenever a full window is scanned there may be more records to process, so BatchedJob
# enqueues a follow-up run to continue from where this run left off. When run without arguments, processing starts at
# the beginning of the `integrations` table.
class CleanupOrphanedIntegrationsJob < BatchedJob
  queue_as :cleanup_orphaned_integrations
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # Max number of Integration records to scan per run before BatchedJob enqueues a follow-up to continue.
  BATCH_SIZE = 10_000

  # Number of Integration records to load per query while scanning within a single run. Keeps the owner ID lookups
  # (and the amount of data held in memory at once) bounded.
  SCAN_BATCH_SIZE = 1_000

  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # This job is exempt from the tenant context requirement because it is used to clean up orphaned records regardless
  # of the tenant.
  exempt_from_tenant_context_requirement

  # Public: The batch object returned by #next_batch. Its #size reports the number of records *scanned* in the window
  # (not the number of orphans found), which is what BatchedJob#record_batch_size and the default
  # BatchedJob#has_next_batch? call to decide whether to enqueue a follow-up run once a full BATCH_SIZE window has
  # been scanned.
  class OrphanScanResult < T::Struct
    prop :size, Integer
    prop :orphaned_integration_ids, T::Array[Integer]
    prop :last_scanned_id, Integer
  end

  # Public: Scans up to BATCH_SIZE Integrations after the cursor (in SCAN_BATCH_SIZE chunks) and returns the orphans found.
  sig do
    params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped)
      .returns(OrphanScanResult)
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    scan_integrations_for_orphans(offset_item_id)
  end

  # Public: Destroys the orphans identified by #next_batch and reports the outcome.
  sig { params(batch: OrphanScanResult, args: T.untyped, offset_item_id: Integer, options: T.untyped).void }
  def process_batch(batch, *args, offset_item_id: 0, **options)
    destroyed_integration_ids = destroy_orphans(batch.orphaned_integration_ids)
    end_id = has_next_batch?(batch, **options) ? batch.last_scanned_id : nil

    report_result(
      identified_ids: batch.orphaned_integration_ids,
      destroyed_ids: destroyed_integration_ids,
      start_id: offset_item_id,
      end_id: end_id,
    )
  end

  # Public: Cursor for the follow-up run: resume after the last Integration scanned in this window.
  sig { params(batch: OrphanScanResult, args: T.untyped, options: T.untyped).returns(Integer) }
  def next_batch_offset_item_id(batch, *args, **options)
    batch.last_scanned_id
  end

  private

  sig { params(start_id: Integer).returns(OrphanScanResult) }
  def scan_integrations_for_orphans(start_id)
    orphaned_integration_ids = []
    last_scanned_id = T.let(start_id, Integer)
    scanned_count = T.let(0, Integer)

    load_integrations_batch(start_id) do |integrations|
      orphaned_integration_ids.concat(orphaned_ids_from(integrations))
      last_scanned_id = T.must(integrations.last).id
      scanned_count += integrations.size
    end

    OrphanScanResult.new(orphaned_integration_ids: orphaned_integration_ids, last_scanned_id: last_scanned_id,
      size: scanned_count)
  end

  sig { params(after_id: Integer, block: T.proc.params(batch: T::Array[Integration]).void).void }
  def load_integrations_batch(after_id, &block)
    outer_batch = Integration.select(:id, :owner_id, :owner_type).where("id > ?", after_id).limit(BATCH_SIZE)
    outer_batch.find_in_batches(batch_size: SCAN_BATCH_SIZE) do |batch|
      yield(batch)
    end
  end

  # Private: Returns the IDs of the given Integrations whose owner no longer exists. Integrations owned by a
  # soft-deleted Business are NOT considered orphaned.
  sig { params(integrations: T::Array[Integration]).returns(T::Array[Integer]) }
  def orphaned_ids_from(integrations)
    orphaned_ids = []

    # polymorphic owners are stored by base class, so Organizations are recorded with owner_type=User
    user_owned = integrations.select(&:user_or_organization_owned?)
    if user_owned.any?
      all_user_owner_ids = user_owned.map(&:owner_id).uniq
      valid_user_owner_ids = User.where(id: all_user_owner_ids).pluck(:id).to_set
      orphaned_ids.concat(user_owned.reject { |i| valid_user_owner_ids.include?(i.owner_id) }.map(&:id))
    end

    business_owned = integrations.select(&:enterprise_owned?)
    if business_owned.any?
      all_business_owner_ids = business_owned.map(&:owner_id).uniq
      # Business.unscoped so soft-deleted Businesses still count as valid owners and their apps aren't removed.
      valid_business_owner_ids = Business.unscoped.where(id: all_business_owner_ids).pluck(:id).to_set
      orphaned_ids.concat(business_owned.reject { |i| valid_business_owner_ids.include?(i.owner_id) }.map(&:id))
    end

    orphaned_ids
  end

  # Private: Loads the identified orphans as full records and destroys them, returning the IDs that were removed.
  sig { params(orphaned_integration_ids: T::Array[Integer]).returns(T::Array[Integer]) }
  def destroy_orphans(orphaned_integration_ids)
    result = []
    return result if orphaned_integration_ids.empty?

    Integration.where(id: orphaned_integration_ids).find_in_batches(batch_size: SCAN_BATCH_SIZE) do |integrations|
      result.concat(destroy_batch_of_orphans(integrations))
    end
    result
  end

  sig { params(integrations: T::Array[Integration]).returns(T::Array[Integer]) }
  def destroy_batch_of_orphans(integrations)
    result = []
    prefill_integrations_for_destroy(integrations)

    with_write do
      Integration.throttle do
        integrations.each do |integration|
          integration.destroy
          result << integration.id if integration.destroyed?
        end
      end
    end

    result
  end

  sig { params(integrations: T::Array[Integration]).void }
  def prefill_integrations_for_destroy(integrations)
    # Integration#destroy destroys the associated Bot via Integration#destroy_bot, so prefilling `bot` turns a
    # per-record Bot lookup into a single query for the batch.
    GitHub::PrefillAssociations.prefill_associations(integrations, :bot)

    # Some destroy callbacks read Integration#owner (e.g. Proxima::Syncable#owner). Prefilling the polymorphic
    # `owner` collapses that per-record owner lookup into one query per owner type for the batch.
    GitHub::PrefillAssociations.prefill_associations(integrations, :owner)
  end

  sig do
    params(
      identified_ids: T::Array[Integer],
      destroyed_ids: T::Array[Integer],
      start_id: Integer,
      end_id: T.nilable(Integer)
    ).void
  end
  def report_result(identified_ids:, destroyed_ids:, start_id:, end_id:)
    all_removed = destroyed_ids.size == identified_ids.size
    had_prev_batch = start_id > 0
    has_next_batch = end_id.present?
    tags = ["all_removed:#{all_removed}", "attempted_removal:true",
      "had_prev_batch:#{had_prev_batch}", "has_next_batch:#{has_next_batch}"]

    GitHub.dogstats.distribution("cleanup_orphaned_integrations_job.orphaned_integrations",
      identified_ids.size, tags: tags)

    GitHub.logger.info(
      {
        "gh.job.name" => self.class.name,
        "identified_orphaned_integration_ids" => identified_ids.sort,
        "removed_orphaned_integration_ids" => destroyed_ids.sort,
        "all_removed" => all_removed,
        "attempted_removal" => true,
        "start_id" => start_id,
        "end_id" => end_id,
      }
    )
  end
end
