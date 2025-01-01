# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class StartOrganizationMigration < Platform::Mutations::Base
      description "Starts a GitHub Enterprise Importer organization migration."

      minimum_accepted_scopes ["read:enterprise", "admin:org", "repo", "workflow"]

      argument :source_org_url, Platform::Scalars::URI, "The URL of the organization to migrate.", required: true
      argument :target_org_name, String, "The name of the target organization.", required: true
      argument :target_enterprise_id, ID, "The ID of the enterprise the target organization belongs to.", required: true, loads: Objects::Enterprise
      argument :source_access_token, String, "The migration source access token.", required: true

      field :org_migration, Objects::OrganizationMigration, "The new organization migration.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, target_enterprise:, **inputs)
        permission.access_allowed?(
          :octoshift_enterprise_import,
          resource: target_enterprise,
          current_org: nil,
          current_repo: nil
        )
      end

      def resolve(target_enterprise:, **inputs)
        validate_access!(target_enterprise)

        target_org_name = inputs[:target_org_name].parameterize(preserve_case: true)

        validate_name!(target_org_name)

        begin
          faraday_connection = Octoshift::Twirp::ConnectionBuilder
            .for_enterprise(target_enterprise)
            .build

          start_org_migration_client = ::Octoshift::Twirp::StartOrganizationMigrationClient.new(faraday_connection: faraday_connection)

          org_migration = start_org_migration_client.start_org_migration(
            user_id: context[:viewer].id,
            target_org_name: target_org_name,
            target_enterprise_id: target_enterprise.id,
            source_access_token: inputs[:source_access_token],
            target_access_token: context[:request_token],
            source_org_url: inputs[:source_org_url].to_s
          )
        rescue Faraday::ConnectionFailed
          Octoshift::DatadogHelper.send_service_unavailable_stats(target_enterprise)
          raise(Errors::ServiceUnavailable, "GitHub Enterprise Importer is currently unavailable. Please try again later.")
        rescue Octoshift::Twirp::Error => e
          raise Errors::Unprocessable.new(e.message)
        end

        # Create wrapper object for twirp response
        org_migration = ::Octoshift::OrganizationMigration.new(org_migration)

        GitHub.logger.info("Created organization migration",
          {
            "gh.request_id": GitHub.context[:request_id],
            "gh.migration_tools.migration.type": "org",
            "gh.migration_tools.migration.id": org_migration.id,
            "gh.migration_tools.migration.database_id": org_migration.database_id,
          })

        { org_migration: org_migration }
      end

      def validate_access!(target_enterprise)
        viewer = context[:viewer]

        ensure_business_not_suspended!(target_enterprise)
        ensure_business_payment_completed!(target_enterprise)

        unless target_enterprise.owner?(viewer)
          raise Errors::Forbidden.new("#{viewer.display_login} does not have permission to create organizations for this enterprise.")
        end

        allows_octoshift = Octoshift::ValidationHelper.allows_octoshift_ips?(target_enterprise)

        unless allows_octoshift
          raise Errors::Unprocessable.new("Migrations failed due to IP allow list enforcement on the target organization. Please see the following documentation to allow the required IP ranges for migrations and try again: https://docs.github.com/migrations/using-github-enterprise-importer/preparing-to-migrate-with-github-enterprise-importer/managing-access-for-github-enterprise-importer#configuring-ip-allow-lists-for-migrations.")
        end
      end

      def validate_name!(target_org_name)
        if target_org_name.blank?
          raise Errors::Unprocessable.new("Organization name cannot be blank.")
        end

        if target_org_name.length > User::LOGIN_MAX_LENGTH
          raise Errors::Unprocessable.new("Organization name cannot be longer than #{User::LOGIN_MAX_LENGTH} characters.")
        end

        if ReservedLogin.reserved? target_org_name
          raise Errors::Unprocessable.new("Organization name #{target_org_name} is unavailable.")
        end

        unless target_org_name.match?(User::LOGIN_REGEX)
          raise Errors::Unprocessable.new("The name #{target_org_name} #{User::LOGIN_VALIDATION_MESSAGE}.")
        end

        if User.find_by_login(target_org_name).present?
          raise Errors::Unprocessable.new("The name #{target_org_name} is already taken.")
        end
      end
    end
  end
end
