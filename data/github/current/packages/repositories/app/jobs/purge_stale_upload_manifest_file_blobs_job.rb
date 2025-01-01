# typed: true
# frozen_string_literal: true

class PurgeStaleUploadManifestFileBlobsJob < ApplicationJob
  queue_as :purge_stale_upload_manifest_file_blobs

  schedule interval: 1.hour, condition: -> { GitHub.storage_cluster_enabled? }

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  class << self
    attr_accessor :purge_batch_size
    attr_accessor :ttl
  end
  PURGE_BATCH_SIZE = 100
  TTL = 24.hours

  def expire_batch
    UploadManifest.joins(:files).
      where("commit_oid is null AND upload_manifests.updated_at < ? AND storage_blob_id is not null", TTL.ago).
      limit(PURGE_BATCH_SIZE).distinct
  end

  def perform
    while expire_batch.count != 0
      expire_batch.each do |manifest|
        with_write { manifest.cleanup }
      end
    end
  end
end
