# typed: true
# frozen_string_literal: true

class RepositoryCopyLanguageStatsJob < ApplicationJob
  queue_as :repository_copy_language_stats

  retry_on_dirty_exit

  # Copies the language stats of an existing repo to a newly created repo
  #
  # repo_id - The repository id of the new repo
  # copy_from_repo_id - The repository id of the repo to copy from
  #
  # Returns nothing.
  def perform(repo_id, copy_from_repo_id:)
    repo = if FeatureFlag.vexi.enabled?(:repos_domain_find_by, default: false)
      T.cast(Repositories.domain.by_id(repo_id), T.nilable(Repository)) # rubocop:todo GitHub/AvoidCast
    else
      Repository.find_by(id: repo_id)
    end
    return if repo.nil?

    with_write { repo.copy_language_stats_from_repo(copy_from_repo_id) }
  end
end
