# typed: true
# frozen_string_literal: true

module Api::Serializer::MigrationsDependency
  extend T::Helpers

  # For the purposes of the performance experiment, we only care about these keys
  # in the repository hash.
  SCIENCE_REPO_IDENTITY_KEYS = %i[
    id
    node_id
    name
    full_name
    private
    owner
    html_url
    description
    fork
    url
  ]

  requires_ancestor { Api::Serializer }

  include Api::Serializer::RepositoriesDependency
  include Scientist

  # Creates a Hash to be serialized to JSON.
  def migration_hash(migration, options = {})
    options = Api::SerializerOptions.from(options)
    repos   = migration.repositories
    path    = if migration.owner.organization?
      "/orgs/#{migration.owner.login_for_api}/migrations/#{migration.id}"
    else
      "/user/migrations/#{migration.id}"
    end

    hash = {
      id: migration.id,
      node_id: global_id_for(migration, options),
      owner: user_hash(migration.owner, content_options(options)),
      guid: migration.guid,
      state: migration.current_state.name,
      lock_repositories: migration.lock_repositories,
      exclude_metadata: migration.exclude_metadata,
      exclude_git_data: migration.exclude_git_data,
      exclude_attachments: migration.exclude_attachments,
      exclude_releases: migration.exclude_releases,
      exclude_owner_projects: migration.exclude_owner_projects,
      org_metadata_only: migration.org_metadata_only,
      repositories: [],
      url: url(path, options),
    }

    unless coerce_array(options[:exclude]).include?("repositories")
      hash[:repositories] = repos.map do |repo|
        if options.changeset_active?(:restrict_repo_fields_in_migration_resource)
          simple_repository_hash(repo, options)
        else
          repository_hash(repo, options)
        end
      end
    end

    if migration.exported? && migration.file.present?
      hash[:archive_url] = url("#{path}/archive", options)
    end

    hash[:created_at] = migration.created_at
    hash[:updated_at] = migration.updated_at

    hash
  end

  private

  # Internal: coerces a comma delimited string, nil, or array into an array
  def coerce_array(obj)
    if obj.is_a?(String)
      obj.split(",")
    else
      Array.wrap(obj)
    end
  end
end
