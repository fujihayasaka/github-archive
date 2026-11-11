# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class StartImport < Platform::Mutations::Base
      include Helpers::LegacyMigration

      description "Starts an import of GitHub data"

      feature_flag :gh_migrator_import_to_dotcom

      minimum_accepted_scopes ["admin:org"]

      argument :organization_id, ID, "The Node ID of the importing organization.", required: true, loads: Objects::Organization

      field :migration, Objects::LegacyMigration, "The pending import migration.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, organization:, **inputs)
        org = organization
        permission.access_allowed?(:migration_import, resource: org, organization: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
      end

      def resolve(organization:, **inputs)
        unless feature_flag_enabled?(organization)
          raise Errors::Forbidden.new("Organization #{organization.display_login} is not authorized to perform imports.")
        end

        unless organization.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} does not have permission to import to #{organization.display_login}.")
        end

        migration = Migration.new
        migration.owner = organization
        migration.creator = context[:viewer]
        migration.guid = SecureRandom.uuid
        migration.state = 40 # :waiting for import to start

        if migration.save
          { migration: migration }
        else
          raise Errors::Unprocessable.new("Could not start the import migration: " +
            migration.errors.full_messages.join(", "))
        end
      end
    end
  end
end
