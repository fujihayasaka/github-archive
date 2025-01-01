# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class PinEnvironment < Platform::Mutations::Base
      description "Pin an environment to a repository"
      visibility :public
      minimum_accepted_scopes ["public_repo"]

      argument :environment_id, ID, "The ID of the environment to modify", required: true, loads: Objects::Environment
      argument :pinned, Boolean, "The desired state of the environment. If true, environment will be pinned. If false, it will be unpinned.", required: true

      field :environment, Objects::Environment, "The environment that was pinned", null: true
      field :pinned_environment, Objects::PinnedEnvironment, "The pinned environment if we pinned", null: true
      error_fields

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

      def resolve(environment:, pinned:)
        viewer = context[:viewer]

        environment.async_repository.then do |repository|
          unless repository.can_pin_environments?(viewer)
            raise Platform::Errors::Forbidden.new("Actor must be writer of repository environments to pin Environment")
          end

          if repository.locked_on_migration?
            raise Errors::Unprocessable::RepositoryMigration.new
          end

          if repository.archived?
            raise Errors::Unprocessable::RepositoryArchived.new
          end

          if repository.environments&.count == 0
            raise Platform::Errors::Validation.new("There are no environments to pin")
          end

          if pinned && repository.pinned_environments&.count >= Repository::PinnedEnvironmentsDependency::PINNED_ENVIRONMENTS_LIMIT
            raise Platform::Errors::Unprocessable.new("Maximum #{Repository::PinnedEnvironmentsDependency::PINNED_ENVIRONMENTS_LIMIT} pinned environments per repository")
          end

          success = if pinned
            environment.pin(actor: viewer)
          else
            environment.unpin(actor: viewer)
          end

          if success
            environment.reload
            {
              environment: environment,
              pinned_environment: environment.pinned_environment,
              errors: [],
            }
          else
            raise Platform::Errors::Unprocessable.new("Pinned environments could not be changed at this time")
          end
        end
      end
    end
  end
end
