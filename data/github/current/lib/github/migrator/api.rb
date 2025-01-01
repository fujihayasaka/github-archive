# typed: true
# frozen_string_literal: true

require "github/migrator"

module GitHub
  class Migrator
    # Support for the public API.
    class Api
      URL_REGEX = URI.regexp(%w[http https])
      MAX_RETRIES = 5.freeze

      attr_reader :guid, :repositories, :mappings, :archive_path, :exclude_metadata, :exclude_git_data, :exclude_attachments, :exclude_releases, :exclude_owner_projects, :org_metadata_only

      def initialize(options)
        # The User id for the actor performing the migration.
        @actor_id = options.fetch("actor_id")
        # The User or Org id that owns the migration.
        @owner_id = options.fetch("owner_id")
        # Identify the export session.
        @guid = options.fetch("guid")
        # Repositories should be URLs, so parse them as URLs, but keep them as strings.
        @repositories = options.fetch("repositories").each { |repository| URI(repository) }
        # Mappings should be hashes
        @mappings = options["mappings"]
        # Ensure that we'll be able to write to the archive.
        @archive_path = options.fetch("archive_path")
        File.open(archive_path, "a") {} # Ensure it's writable.
        # Boolean indicating whether to exclude metadata and just include git source.
        @exclude_metadata = options.fetch("exclude_metadata", false)
        # Boolean indicating whether to exclude the repository git source or not.
        @exclude_git_data = options.fetch("exclude_git_data", false)
        # Boolean indicating whether to include attachments or not.
        @exclude_attachments = options.fetch("exclude_attachments", false)
        # Boolean indicating whether to include releases or not.
        @exclude_releases = options.fetch("exclude_releases", false)
        # Boolean indicating whether to include owner-level projects or not.
        @exclude_owner_projects = options.fetch("exclude_owner_projects", false)
        # Boolean indicating whether to override other variables and only export org data.
        @org_metadata_only = options.fetch("org_metadata_only", false)
      end

      # Do the import.
      #
      # Called after github/github and gh-migrator are loaded.
      def run
        db_nice do
          # TODO hook into progress events (`migrator.on_progress_with_count { |count| ... }`)
          # TODO generate stats

          migrator.add_user_to_export(owner)

          if org_metadata_only
            migrator.add_organization_to_export(owner)
          end

          repositories.each do |repository|
            migrator.add_to_export(
              repository,
              {
                exclude_metadata: exclude_metadata,
                exclude_attachments: exclude_attachments,
                exclude_releases: exclude_releases,
                exclude_owner_projects: exclude_owner_projects,
                exclude_git_data: exclude_git_data,
                org_metadata_only: org_metadata_only
              }
            )
            sleep 10 unless Rails.env.test?
          end

          migrator.export! unless ::Migration.export_disabled_for_actor?(actor)
        end
      end

      # Do the mappings.
      #
      # Called after github/github and gh-migrator are loaded.
      def run_map
        mappings_processed_count, warnings_count = 0, 0
        messages = []

        mappings.each do |mapping|
          success, message = process_mapping(mapping)

          if success
            mappings_processed_count += 1
          else
            warnings_count += 1
          end

          messages.push(message)
        end

        # Batch in the remaining recordsProcessed % BATCH_SIZE models that have
        # not been updated
        migrator.import_mapper.process_batch

        retries_remaining = MAX_RETRIES

        begin
          check_for_conflicts!
        rescue Workflow::NoTransitionAllowed
          if retries_remaining.zero?
            raise
          else
            retries_remaining -= 1
            sleep retry_sleep_time(retries_remaining) unless Rails.env.test?
            retry
          end
        end

        {
          recordsProcessed: mappings_processed_count,
          warnings: warnings_count,
          messages: messages.compact,
        }
      end

      def check_for_conflicts!
        migration.reload
        if migrator.conflicts?(organization: owner)
          # Set state to conflicts
          migration.conflicts_detected!
        else
          # No more conflicts, return that we are ready for import
          migration.resolve_conflicts!
        end
      end

      private

      def raw_mapping(mapping)
        mapping.map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
      end

      def process_mapping(mapping)
        unless valid_mapping?(mapping)
          return [false, %(#{mapping["action"]}: invalid input `#{raw_mapping(mapping)}`)]
        end

        begin
          db_nice do
            migrator.map(
              mapping["source_url"],
              mapping["target_url"],
              mapping["action"].to_sym,
              mapping["model_name"],
              organization:   owner,
              batch_mappings: true,
            )
          end
        rescue CannotMapToMissingTarget,  # tried mapping to a target_url that doesn't exist
            CannotRenameToExistingModel,  # tried to rename to a name that is already taken
            FailedMapping => error  # unsupported mapping action or could not infer model name from url
          return [
            false,
            %(map: couldn't map `#{raw_mapping(mapping)}`: #{error.message}),
          ]
        end
        true
      end

      def valid_mapping?(mapping)
        return false unless %w(model_name source_url target_url action).all? do |key|
          mapping[key].present?
        end
        mapping["source_url"] =~ URL_REGEX && mapping["target_url"] =~ URL_REGEX
      end

      def retry_sleep_time(retries_remaining)
        2**(MAX_RETRIES - retries_remaining)
      end

      def db_nice
        ActiveRecord::Base.connected_to(role: :reading) do
          MigratableResource.throttle do
            yield
          end
        end
      end

      # Internal: The User performing the migration.
      #
      # Returns a User.
      def actor
        User.find(@actor_id)
      end

      # Internal: Instance of GitHub::Migrator to perform commands on.
      def migrator
        @migrator ||= GitHub::Migrator.new(
          actor: actor,
          owner: owner,
          guid: guid,
          migration_path: (ENV["GH_MIGRATOR_STAGING_DIR"] || Pathname(GitHub.migration_file_staging_path).join(guid).to_s),
          archive_export_path: archive_path,
          exclude_git_data: exclude_git_data,
          org_metadata_only: org_metadata_only,
          exclude_metadata: exclude_metadata,
        )
      end

      def migration
        @migration ||= ::Migration.find_by(guid: guid)
      end

      # Internal: The owner of the migration
      #
      # Returns a User or Organization.
      def owner
        @owner ||= User.find(@owner_id)
      end
    end
  end
end
