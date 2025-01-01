# typed: true
# frozen_string_literal: true

module Codespaces
  class HandlePrebuildsWhenRepoDeletedJob < CodespacesJob
    locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC
    retry_on_dirty_exit

    def perform(repository_id:)
      repository = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
        Repositories.domain.by_id(repository_id)
      else
        Repository.find_by(id: repository_id)
      end
      return unless repository.blank? || repository.deleted?

      Codespaces::DeletePrebuildsForRepoJob.perform_later(repository_id: repository_id)

    rescue Aqueduct::Worker::JobKilled => e
      GitHub.dogstats.increment("codespaces.handle_prebuilds_when_repo_deleted.dirty_exit")
      raise
    end
  end
end
