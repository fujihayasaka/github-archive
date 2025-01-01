# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class StartRepositoryMigration < Platform::Mutations::Base
      description "Starts a GitHub Enterprise Importer (GEI) repository migration."

      minimum_accepted_scopes ["admin:org", "read:org", "repo"]

      argument :source_id, ID, "The ID of the migration source.", required: true, loads: Objects::MigrationSource
      argument :owner_id, ID, "The ID of the organization that will own the imported repository.", required: true, loads: Objects::Organization
      argument :source_repository_url, Platform::Scalars::URI, "The URL of the source repository.", required: true
      argument :repository_name, String, "The name of the imported repository.", required: true, validates: { length: { minimum: 1, maximum: 100 } }
      argument :continue_on_error, Boolean, "Whether to continue the migration on error. Defaults to `true`.", required: false
      argument :git_archive_url, String, "The signed URL to access the user-uploaded git archive.", required: false
      argument :metadata_archive_url, String, "The signed URL to access the user-uploaded metadata archive.", required: false
      argument :access_token, String, "The migration source access token.", required: false
      argument :github_pat, String, "The GitHub personal access token of the user importing to the target repository.", required: false
      argument :skip_releases, Boolean, "Whether to skip migrating releases for the repository.", required: false
      argument :target_repo_visibility, String, "The visibility of the imported repository.", required: false
      argument :lock_source, Boolean, "Whether to lock the source repository.", required: false

      field :repository_migration, Objects::RepositoryMigration, "The new repository migration.", null: true

      ALLOWED_ERROR_CODES = ["already_exists"]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, source:, **inputs)
        source.async_owner.then do |owner|
          owner.async_business.then do
            permission.access_allowed?(
              :octoshift_import,
              resource: owner,
              organization: owner,
              current_repo: nil
            )
          end
        end
      end

      def resolve(source:, owner:, **inputs)
        target_validator = Octoshift::TargetValidator.new(
          source: source,
          owner: owner,
          user: context[:viewer],
          github_pat: inputs[:github_pat]
        )

        unless target_validator.owner_matches?
          raise Errors::Forbidden.new("Owner #{owner.display_login} is not scoped under migration source.")
        end

        unless target_validator.user_can_import_repo?
          raise Errors::Forbidden.new("User #{context[:viewer].display_login} is not authorized to perform imports on #{owner.display_login}")
        end

        unless target_validator.pat_valid?
          raise Errors::Forbidden.new("Please make sure that githubPat is a valid PAT")
        end

        unless target_validator.pat_can_import_repo?
          raise Errors::Forbidden.new("Please make sure that the owner of githubPat is authorized to perform imports into #{owner.display_login}")
        end

        if target_validator.missing_pat_scopes.present?
          raise Errors::Forbidden.new("Please make sure that githubPat includes the #{target_validator.missing_pat_scopes.to_sentence} scope")
        end

        if target_validator.pat_needs_sso?
          raise Errors::Forbidden.new("Please make sure that githubPat is SSO-enabled for #{owner.display_login}")
        end

        if validate_ip_allowlist?(owner)
          unless target_validator.owner_has_allowlisted_ips?
            raise Errors::Unprocessable.new("Please add GitHub Enterprise Importer's IP addresses to the allow list for organization #{owner.display_login}. For more details, see https://docs.github.com/migrations/using-github-enterprise-importer/preparing-to-migrate-with-github-enterprise-importer/managing-access-for-github-enterprise-importer#configuring-ip-allow-lists-for-migrations.")
          end
        end

        if target_validator.repository_exists?(inputs[:repository_name]) && !GitHub.flipper[:octoshift_experimental_incremental_migrations].enabled?(owner)
          raise Errors::Validation.new("A repository called #{owner.display_login}/#{inputs[:repository_name]} already exists")
        end

        unless target_validator.valid_visibility?(inputs[:target_repo_visibility])
          raise Errors::Validation.new("Invalid target repository visibility. Must be 'private', 'public', or 'internal'")
        end

        faraday_connection = Octoshift::Twirp::ConnectionBuilder
          .for_organization(owner)
          .build

        start_migration_client = ::Octoshift::Twirp::StartMigrationClient.new(faraday_connection: faraday_connection)

        begin
          repository_migration = start_migration_client.start_migration(
            user_id: context[:viewer].id,
            repository_name: inputs[:repository_name],
            source_connector_id: source.id,
            source_identifier_url: inputs[:source_repository_url].to_s,
            continue_on_error: inputs.fetch(:continue_on_error, true),
            git_archive_url: inputs.fetch(:git_archive_url, ""),
            metadata_archive_url: inputs.fetch(:metadata_archive_url, ""),
            access_token: inputs[:access_token],
            github_pat: inputs.fetch(:github_pat, ""),
            skip_releases: inputs.fetch(:skip_releases, false),
            target_repo_visibility: inputs.fetch(:target_repo_visibility, "private"),
            lock_source: inputs.fetch(:lock_source, false)
          )
        rescue Faraday::ConnectionFailed => e
          log_exception(e)
          Octoshift::DatadogHelper.send_service_unavailable_stats(owner)
          raise(Errors::ServiceUnavailable, "GitHub Enterprise Importer is currently unavailable. Please try again later.")
        rescue Octoshift::Twirp::Error => e
          log_exception(e)
          message_substring = e.message.slice(/\"(.*)"/)
          if message_substring.present? && ALLOWED_ERROR_CODES.any? { |code| e.message.include?(code) }
            raise Errors::Validation.new(message_substring.tr('"', ""))
          else
            raise Errors::InternalExecution.new(e.message)
          end
        rescue => e
          log_exception(e)
          raise e # rubocop:disable GitHub/UsePlatformErrors
        end

        set_batched_migration_state(repository_migration, owner, inputs[:repository_name], inputs[:source_repository_url].to_s)

        # Create wrapper object for twirp response
        repository_migration = ::Octoshift::RepositoryMigration.new(repository_migration, source)

        GitHub.logger.info("Created repository migration",
          {
            "gh.migration_tools.migration.type": "repo",
            "gh.migration_tools.migration.database_id": repository_migration.database_id,
            "gh.request_id": GitHub.context[:request_id],
            "user_agent.original": GitHub.context[:user_agent].to_s,
          })

        { repository_migration: repository_migration }
      end

      private

      def validate_ip_allowlist?(owner)
        GitHub.flipper[:octoshift_validate_ip_allowlist_in_start_repository_migration_mutation].enabled?(owner) ||
            (owner.business.present? && GitHub.flipper[:octoshift_validate_ip_allowlist_in_start_repository_migration_mutation].enabled?(owner.business))
      end

      def log_exception(exception)
        # rubocop:disable Style/HashSyntax
        GitHub.logger.error("Handled exception in startRepositoryMigration mutation", exception: exception, "gh.request_id" => GitHub.context[:request_id])
      end

      def set_batched_migration_state(repository_migration, owner, repo_name, source_repo_url)
        return unless GitHub.flipper[:octoshift_experimental_incremental_migrations].enabled?(owner)
        target_repo_nwo = "#{owner.display_login}/#{repo_name}"
        current_target_repo_state = OctoshiftBatchHelper::TargetRepoState.fetch(target_repo_nwo)
        current_target_repo_state.set_current_octoshift_migration_id(repository_migration.id)

        OctoshiftBatchHelper::MigrationState.create(
          repository_migration.id,
          "#{owner.display_login}/#{repo_name}",
          source_repo_url,
          current_target_repo_state&.current_cursor || 0
        )
      end
    end
  end
end
