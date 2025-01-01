# typed: true
# frozen_string_literal: true

# Serially restores a list of repositories.
class BulkRepositoryRestoreJob < ApplicationJob
  queue_as :archive_restore

  def self.prefix
    "bulk_repository_restore"
  end

  def self.job_id(ids)
    "#{prefix}_#{ids.first}"
  end

  def self.status(ids)
    Repositories::JobStatus.find(BulkRepositoryRestoreJob.job_id(ids))
  end

  def perform(ids, user_id)
    status = BulkRepositoryRestoreJob.status(ids)
    return unless status
    return unless ids.present?

    status.track do
      repo_id = ids.shift
      with_write do
        Repository.restore(repo_id, actor: User.new(id: user_id), synchronous: false)
      end
      # create next job to continue bulk restore
      if ids.present?
        Repositories::JobStatus.create(id: BulkRepositoryRestoreJob.job_id(ids))
        BulkRepositoryRestoreJob.perform_later(ids, user_id)
      end
    end
  end
end
