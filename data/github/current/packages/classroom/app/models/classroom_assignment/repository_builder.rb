# typed: true
# frozen_string_literal: true

module ClassroomAssignment::RepositoryBuilder
  class FailedRepositoryCreationError < StandardError; end

  # Public: Builds a repository from the attributes of the provided source_repo
  #
  # The returned object is saved.
  #
  # Returns Repository
  def self.perform(classroom_assignment, source_repo, actor, org)
    raise ArgumentError, "classroom_assignment cannot be nil" unless classroom_assignment
    raise ArgumentError, "actor cannot be nil" unless actor
    raise ArgumentError, "org cannot be nil" unless org
    raise ArgumentError, "source_repo cannot be nil" unless source_repo

    repo_name = if org.repositories.where(name: source_repo.name).exists?
      "#{source_repo.name}-#{SecureRandom.hex(3)}"
    else
      source_repo.name
    end

    result = Repository.handle_creation(
      actor,
      org,
      {
        name: repo_name,
        private: source_repo.private?,
        owner: org,
        parent: nil,
        network: nil,
        created_by_user_id: actor.id,
        has_issues: source_repo.has_issues,
        has_wiki: source_repo.has_wiki,
        has_downloads: source_repo.has_downloads,
        has_projects: source_repo.has_projects,
        repository_license: source_repo&.repository_license&.dup,
        updated_at: source_repo.updated_at,
        pushed_at: source_repo.pushed_at,
        pushed_at_usec: source_repo.pushed_at_usec,
        disk_usage: source_repo.disk_usage,
        primary_language_name_id: source_repo.primary_language_name_id,
        template: source_repo.template,
        classroom_assignment: classroom_assignment,
      },
      {},
      nil,
      skip_validation: true,
      source_repository: source_repo
    )

    raise FailedRepositoryCreationError.new(result.error_message) if !result.success?

    result.repository
  end
end
