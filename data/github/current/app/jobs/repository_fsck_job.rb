# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

class RepositoryFsckJob < ApplicationJob
  queue_as :repository_fsck
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  def perform(repo_id)
    repository = if FeatureFlag.vexi.enabled?(:repos_by_id_jobs, default: false)
      Repositories.domain.by_id(repo_id)
    else
      Repository.find_by_id(repo_id)
    end
    repository&.fsck!
  end
end
