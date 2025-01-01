# typed: false
# frozen_string_literal: true

class RepositoryCopyLanguageStatsJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :repository_copy_language_stats

  retry_on_dirty_exit

  # Copies the language stats of an existing repo to a newly created repo
  #
  # repo_id - The repository id of the new repo
  # copy_from_repo_id - The repository id of the repo to copy from
  #
  # Returns nothing.
  def perform(repo_id, copy_from_repo_id:)
    repo = Repository.find_by_id(repo_id)
    return if repo.nil?

    repo.copy_language_stats_from_repo(copy_from_repo_id)
  end
end
