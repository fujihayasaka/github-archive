# typed: true
# frozen_string_literal: true

module ClassroomRepository::RepositoryBuilder
  FIELDS_COPIED_FROM_STARTER_REPOSITORY = %w(
    updated_at
    pushed_at
    pushed_at_usec
    disk_usage
    primary_language_name_id
  ).freeze

  class FailedRepositoryCreationError < StandardError; end

  # Public: Builds a repository from the given attributes.
  #
  # The returned object is saved.
  #
  # Returns Repository
  def self.perform(classroom_repo, actor, org, repo_name, is_private, starter_repo)
    raise ArgumentError, "classroom_repo cannot be nil" unless classroom_repo
    raise ArgumentError, "actor cannot be nil" unless actor
    raise ArgumentError, "org cannot be nil" unless org
    raise ArgumentError, "repo_name cannot be nil" unless repo_name
    raise ArgumentError, "is_private cannot be nil" if is_private.nil?

    attributes = starter_repo ? starter_repo.attributes.slice(*FIELDS_COPIED_FROM_STARTER_REPOSITORY) : {}

    result = Repository.handle_creation(
      actor,
      org,
      attributes.merge({
        name: repo_name,
        private: is_private,
        owner: org,
        parent: nil,
        network: nil,
        created_by_user_id: actor.id,
        has_issues: true,
        has_wiki: true,
        has_downloads: true,
        has_projects: true,
        repository_license: starter_repo&.repository_license&.dup,
      }),
      {},
      nil,
      skip_validation: true,
      source_repository: starter_repo
    )

    raise FailedRepositoryCreationError.new(result.error_message) if !result.success?

    classroom_repo.repository = result.repository

    raise FailedRepositoryCreationError.new(classroom_repo.errors.full_messages.to_sentence) if !classroom_repo.save

    result.repository
  end
end
