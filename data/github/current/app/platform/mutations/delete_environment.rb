# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteEnvironment < Platform::Mutations::Base
      description "Deletes an environment"

      minimum_accepted_scopes ["public_repo"]

      argument :id, ID, "The Node ID of the environment to be deleted.", required: true, loads: Objects::Environment, as: :environment

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, environment:, **inputs)
        repo = environment.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:write_admin_actions_repo,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(environment:, **inputs)
        environment.destroy!
        {}
      end
    end
  end
end
