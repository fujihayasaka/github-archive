# typed: true
# frozen_string_literal: true

module VariantAnalysis::RepositoryValidationHelper

  REPOSITORIES_COUNT_LIMIT = 1000

  def partition_on_existing_repos(repo_ids)
    existing_repo_ids = repo_ids.each_slice(5000).flat_map { |_ids| Repository.where(id: repo_ids).pluck(:id) }
    [existing_repo_ids, repo_ids - existing_repo_ids]
  end

  def partition_on_controller_repo_privacy(repo_ids, controller_repo)
    return repo_ids, [] if controller_repo.private?

    repo_visibility = repo_ids.each_slice(5000).flat_map { |ids| Repository.where(id: ids).pluck(:id, :public) }.to_h
    repo_ids.partition { |id| repo_visibility[id] }
  end

  def partition_on_db_availability(repo_ids, language)
    existing_databases = CodeqlDatabase.repos_and_languages_with_database(repo_ids.map { |repo_id| [repo_id, language] })
    repo_ids.partition { |repo_id| existing_databases.include?([repo_id, language]) }
  end

  def partition_on_max_repos(repo_ids)
    return repo_ids, [] if repo_ids.length <= REPOSITORIES_COUNT_LIMIT

    included_repo_ids = Repository.where(id: repo_ids).order(pushed_at: :desc).limit(REPOSITORIES_COUNT_LIMIT).pluck(:id)
    [included_repo_ids, repo_ids - included_repo_ids]
  end
end
