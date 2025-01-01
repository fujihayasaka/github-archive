# typed: true
# frozen_string_literal: true

class DeletePurgedMediaBlobsJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  schedule interval: 1.hour, condition: -> { GitHub.storage_cluster_enabled? }

  queue_as :lfs

  retry_on_dirty_exit

  BATCH_SIZE = 100

  def purge_batch(start)
    results = T.let([], T::Array[Media::Blob])
    query = Media::Blob.where(state: Media::Blob.states[:archived])
    unless start.nil?
      query = query.where("id >= ?", start)
    end
    query.find_in_batches(batch_size: BATCH_SIZE) do |batch|
      # Find all the storage blob IDs related to this batch.
      sb_ids = batch.map(&:storage_blob_id)
      # Make a set of existing storage blob IDs.
      blobs = Storage::Blob.where(id: sb_ids).pluck(:id).to_set
      # Reject all media blobs which have an existing storage blob and add the
      # remainder to the list of results.
      results += batch.reject { |item| blobs.include? item.storage_blob_id }
      break if results.length >= BATCH_SIZE
    end
    results
  end

  def perform(start: nil)
    return if GitHub::Enterprise.backup_in_progress?
    # This is an extra sanity check.  If the storage cluster is not enabled
    # (e.g., on dotcom production), the storage_blob_id field will always be
    # NULL and this job will (slowly) delete all Media::Blob records.
    return unless GitHub.storage_cluster_enabled?

    to_purge = purge_batch(start).to_a
    to_purge.each do |blob|
      blob.destroy
    end

    if to_purge.count > 0
      next_offset = to_purge.last.id + 1
      DeletePurgedMediaBlobsJob.perform_later(start: next_offset)
    end
  end
end
