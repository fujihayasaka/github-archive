# typed: true
# frozen_string_literal: true

module Codespaces
  class HandlePrebuildsWhenRepoDeletedJob < CodespacesJob
    locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
    retry_on_dirty_exit

    def perform(repository_id:)
      repository = Repository.find_by(id: repository_id)
      return unless repository.blank? || repository.deleted?

      Codespaces::DeletePrebuildsForRepoJob.perform_later(repository_id: repository_id)

    rescue Aqueduct::Worker::JobKilled => e
      GitHub.dogstats.increment("codespaces.handle_prebuilds_when_repo_deleted.dirty_exit")
      raise
    end
  end
end
