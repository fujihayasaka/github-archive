# typed: true
# frozen_string_literal: true

class UpdateRepositorySponsorablesForGlobalRepoJob < ApplicationJob
  queue_as :update_repository_sponsorables
  retry_on_dirty_exit
  BATCH_SIZE = 100

  def perform(repository_id:)
    return unless repository_id
    return unless GitHub.sponsors_enabled?

    repository = Repositories::Public.find_active(repository_id)
    return unless repository&.global_health_files_repository?

    other_repos_by_owner = Repository.owned_by(repository.owner_id).active.where.not(id: repository.id).select(:id)
    other_repos_by_owner.find_each(batch_size: BATCH_SIZE) do |other_repo|
      UpdateRepositorySponsorablesForRepositoryJob.perform_later(repository_id: other_repo.id)
    end
  end
end
