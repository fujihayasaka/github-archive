# typed: strict
# frozen_string_literal: true

# This Job will purge followers records that are associated with users that no longer exist.
# It processes a single batch per execution and re-enqueues itself to handle the next batch.
class PurgeOrphanedFollowersBatchedJob < BatchedJob
  queue_as :purge_orphaned_followers_batched

  retry_on_dirty_exit

  # This job will run every 24 hours
  schedule interval: 24.hours

  # Don't run more than one of this job at a time
  locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC

  BATCH_SIZE = 5000

  # This job is exempt from tenant scoping as we're solely deleting existing associated records
  exempt_from_tenant_context_requirement

  sig { params(offset_item_id: Integer, options: T.untyped).returns(T::Array[Following]) }
  def next_batch(offset_item_id: 0, **options)
    Following.select(:id, :user_id, :following_id).where("id > ?", offset_item_id).order(:id).limit(BATCH_SIZE).to_a
  end

  sig { params(batch: T::Array[Following], options: T.untyped).void }
  def process_batch(batch, **options)
    return if batch.empty?

    candidate_user_ids = batch.map(&:user_id).uniq
    candidate_following_ids = batch.map(&:following_id).uniq

    existing_user_ids = Users.domain.by_ids(candidate_user_ids).map(&:id).to_set
    existing_following_ids = Users.domain.by_ids(candidate_following_ids).map(&:id).to_set

    orphan_ids = batch.filter_map do |f|
      f.id unless existing_user_ids.include?(f.user_id) && existing_following_ids.include?(f.following_id)
    end

    if orphan_ids.any?
      deleted_count = 0

      with_write do
        deleted_count = Following.where(id: orphan_ids).delete_all
      end

      GitHub.logger.info("Deleted orphaned Following records", {
        "code.namespace" => self.class.name,
        "code.function" => "process_batch",
        "gh.purge_orphaned_followers_batched_job.deleted_count" => deleted_count,
      })
    end
  end
end
