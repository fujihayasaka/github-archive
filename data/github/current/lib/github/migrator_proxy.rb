# typed: true
# frozen_string_literal: true

module GitHub
  # Run gh-migrator.
  #
  # This class is responsible for coordinating with lib/github/migrator to do the
  # export side of migrations.
  class MigratorProxy
    def export(migration:, dest:)
      Dir.mktmpdir("gh-migrator") do |tmpdir|
        config = config(migration: migration, tmpdir: tmpdir, dest: dest)
        config_json = config.to_json

        Failbot.push("gh.migration_tools.gh_migrator.config" => config_json)

        migrator = GitHub::Migrator::Api.new(config)
        migrator.run
      end
    end

    def map(migration:, mappings:, actor:)
      config_map = config_map(migration: migration, mappings: mappings, actor: actor)
      config_json = config_map.to_json

      Failbot.push("gh.migration_tools.gh_migrator.config" => config_json)

      migrator = GitHub::Migrator::Api.new(config_map)
      migrator.run_map
    end

    private

    def config(migration:, tmpdir:, dest:)
      {
        "actor_id" => migration.creator_id,
        "owner_id" => migration.owner_id,
        "guid" => migration.guid,
        "archive_path" => dest,
        "repositories" => migration.repositories.map { |repository| GitHub::Resources.url_for_model(repository) },
        "mappings" => [],
        "exclude_metadata" => migration.exclude_metadata,
        "exclude_git_data" => migration.exclude_git_data,
        "exclude_attachments" => migration.exclude_attachments,
        "exclude_releases" => migration.exclude_releases,
        "exclude_owner_projects" => migration.exclude_owner_projects,
        "org_metadata_only" => migration.org_metadata_only
      }
    end

    def config_map(migration:, mappings:, actor:)
      {
        "actor_id" => actor.id,
        "owner_id" => migration.owner_id,
        "guid" => migration.guid,
        "archive_path" => "/dev/null",
        "repositories" => [],
        "mappings" => mappings,
        "exclude_metadata" => false,
        "exclude_git_data" => false,
        "exclude_attachments" => false,
        "exclude_releases" => false,
        "exclude_owner_projects" => false,
        "org_metadata_only" => false
      }
    end
  end
end
