# typed: true
# frozen_string_literal: true

module RepositoryAdvisory::WorkspaceRepositoryBuilder
  FIELDS_COPIED_FROM_REPOSITORY = %w(
    name
    updated_at
    pushed_at
    pushed_at_usec
    disk_usage
    primary_language_name_id
  ).freeze

  # Public: Builds a security workspace for a repository advisory
  #
  # The security workspace is a `Repository`. The returned object is saved.
  #
  # Returns Repository
  def self.perform(advisory, actor, synchronous: false)
    raise ArgumentError, "actor cannot be nil" unless actor

    repository = advisory.repository

    owner = repository.owner

    attributes = repository.attributes.slice(*FIELDS_COPIED_FROM_REPOSITORY)

    # The name of any repository (including a workspace repository) must be
    # 100 bytes or fewer. To make room for a 19-character GHSA ID and a hyphen
    # to separate it, we need to truncate the original repository's name to
    # 80 characters.
    truncated_repository_name = repository.name.truncate(80, omission: "")
    ghsa_id_suffix = advisory.ghsa_id.downcase
    name = "#{truncated_repository_name}-#{ghsa_id_suffix}"

    workspace_repository_attributes = {
      name: name,
      private: true,
      owner: owner,
      parent: nil,
      network: nil,
      created_by_user_id: actor.id,
      has_issues: false,
      has_wiki: false,
      has_downloads: false,
      has_projects: false,
      repository_license: repository.repository_license&.dup,
      parent_advisory: advisory
    }

    if FeatureFlag.vexi.enabled?(:advisory_db_unrestorable_repositories, repository, default: false) ||
      FeatureFlag.vexi.enabled?(:advisory_db_unrestorable_repositories, actor, default: false)
      workspace_repository_attributes = workspace_repository_attributes.merge({ restorable: false })
    end

    result = Repository.handle_creation(
      actor,
      owner.login, # rubocop:disable GitHub/DoNotAllowLogin
      attributes.merge(workspace_repository_attributes),
      {},
      nil,
      skip_validation: true,
      synchronous: synchronous,
    )

    result.repository
  end
end
