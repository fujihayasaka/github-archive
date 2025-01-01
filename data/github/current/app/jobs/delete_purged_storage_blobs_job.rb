# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class DeletePurgedStorageBlobsJob < ApplicationJob
  schedule interval: 1.hour, condition: -> { GitHub.storage_cluster_enabled? }

  # If we're unable to get the lock then another instance of the job is running and
  # we can safely exit
  discard_on GitHub::Restraint::UnableToLock

  queue_as :storage_cluster

  PURGE_BATCH_SIZE = 100
  LOCK_KEY = name
  LOCK_TIMEOUT = 1.hour

  def perform
    return if GitHub::Enterprise.backup_in_progress?

    to_purge = purge_batch
    purged = with_lock do
      with_write { GitHub::Storage::Destroyer.perform_purge(to_purge) }
    end

    if !purged.nil? && purged.count > 0
      DeletePurgedStorageBlobsJob.perform_later
    end
  end

  private

  def purge_batch
    ::Storage::Purge.where("purge_at <= ?", Time.now).limit(PURGE_BATCH_SIZE)
  end

  def with_lock
    restraint = GitHub::Restraint.new
    restraint.lock!(LOCK_KEY, _lock_concurrency = 1, LOCK_TIMEOUT) do
      yield
    end
  end
end
