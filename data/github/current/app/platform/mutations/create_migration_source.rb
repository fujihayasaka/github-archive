# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateMigrationSource < Platform::Mutations::Base
      description "Creates a GitHub Enterprise Importer (GEI) migration source."

      minimum_accepted_scopes ["admin:org", "read:org", "repo"]

      argument :name, String, "The migration source name.", required: true
      argument :url, String, "The migration source URL, for example `https://github.com` or `https://monalisa.ghe.com`.", required: false
      argument :access_token, String, "The migration source access token.", required: false
      argument :type, Enums::MigrationSourceType, "The migration source type.", required: true
      argument :owner_id, ID, "The ID of the organization that will own the migration source.", required: true, loads: Objects::Organization
      argument :github_pat, String, "The GitHub personal access token of the user importing to the target repository.", required: false

      field :migration_source, Objects::MigrationSource, "The created migration source.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        permission.access_allowed?(
          :octoshift_import,
          resource: owner,
          organization: owner,
          current_repo: nil
        )
      end

      def resolve(owner:, **inputs)
        # Execute twirp call to create migration source
        connection = Octoshift::Twirp::ConnectionBuilder
          .for_organization(owner)
          .build

        connector_client = Octoshift::Twirp::ConnectorClient.new(faraday_connection: connection)

        begin
          connector = connector_client.create_connector(
            name: inputs[:name],
            url: inputs[:url],
            access_token: inputs[:access_token],
            connector_instance_type: inputs[:type],
            owner_id: owner.id,
            # login used for creation, not customer facing
            owner_login: owner.login, # rubocop:disable GitHub/DoNotAllowLogin
            github_pat: inputs[:github_pat]
          )
        rescue Faraday::ConnectionFailed => e
          log_exception(e)
          Octoshift::DatadogHelper.send_service_unavailable_stats(owner)
          raise(Errors::ServiceUnavailable, "GitHub Enterprise Importer is currently unavailable. Please try again later.")
        rescue Octoshift::Twirp::Error => e
          log_exception(e)
          raise Errors::InternalExecution.new(e.message)
        rescue => e
          log_exception(e)
          raise e # rubocop:disable GitHub/UsePlatformErrors
        end

        # Create wrapper object for twirp response
        migration_source = Octoshift::MigrationSource.new(connector)

        GitHub.logger.info("Created migration source",
          {
            "gh.migration_tools.migration.source_id": migration_source.id,
            "gh.request_id": GitHub.context[:request_id],
          })

        { migration_source: migration_source }
      end

      private

      def log_exception(exception)
        # rubocop:disable Style/HashSyntax
        GitHub.logger.error("Handled exception in createMigrationSource mutation", exception: exception, "gh.request_id" => GitHub.context[:request_id])
      end
    end
  end
end
