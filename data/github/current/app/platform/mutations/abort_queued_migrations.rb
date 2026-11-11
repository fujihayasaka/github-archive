# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AbortQueuedMigrations < Platform::Mutations::Base
      description "Clear all of a customer's queued migrations"

      minimum_accepted_scopes ["admin:org"]

      argument :owner_id, ID, "The ID of the organization that is running the migrations.", required: true, loads: Objects::Organization

      field :success, Boolean, "Did the operation succeed?", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :octoshift_admin,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil
        )
      end

      def resolve(owner:, **inputs)
        unless owner.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new("#{context[:viewer].display_login} is not authorized because they are not an admin.")
        end

        migration_client = ::Octoshift::Twirp::MigrationClient.new

        organization = Organization.find(owner.id)
        business = organization.business
        if business.present?
          customer_id = business.slug
          is_business = true
        else
          # disable linter because not customer facing
          customer_id = owner.login # rubocop:disable GitHub/DoNotAllowLogin
          is_business = false
        end

        begin
          migration_client.abort_queued_migrations(
            customer_id: customer_id,
            is_business: is_business
          )
        rescue Octoshift::Twirp::Error => e
          raise Errors::InternalExecution.new(e.message)
        end

        { success: true }
      end
    end
  end
end
