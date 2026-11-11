# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReorderEnvironment < Platform::Mutations::Base
      description "Reorder a pinned repository environment"
      visibility :public
      minimum_accepted_scopes ["public_repo"]

      argument :environment_id, ID, "The ID of the environment to modify", required: true, loads: Objects::Environment
      argument :position, Int, "The desired position of the environment", required: true

      field :environment, Objects::Environment, "The environment that was reordered", null: true
      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, environment:, **inputs)
        repo = environment.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:write_actions_environments_repo,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(environment:, position:)
        pinned_environment = environment.pinned_environment
        repository = environment.repository

        unless repository.can_pin_environments?(context[:viewer])
          raise Platform::Errors::Forbidden.new("Actor must be writer of repository environments to reorder Environment")
        end

        if repository.locked_on_migration?
          raise Errors::Unprocessable::RepositoryMigration.new
        end

        if repository.archived?
          raise Errors::Unprocessable::RepositoryArchived.new
        end

        if pinned_environment.nil?
          raise Platform::Errors::Unprocessable.new("Tried to reorder an environment that is not pinned")
        end

        pinned_environments = repository.pinned_environments.to_a

        pinned_environments.sort! { |a, b| a.position <=> b.position }

        pinned_environments.delete(pinned_environment) do |_|
          raise Platform::Errors::Unprocessable.new("Tried to reorder an environment that is not pinned")
        end

        # Positions start at 1
        pinned_environments.insert(position - 1, pinned_environment)

        pinned_environments.compact!

        pinned_environments.each_with_index do |env, i|
          # Positions start at 1
          env.position = i + 1
        end

        pinned_environments.keep_if(&:changed?)

        if pinned_environments.empty?
          # No work to do, lucky us!
          return {
            environment: environment.reload,
            errors: [],
          }
        end

        cases = pinned_environments.map do |env|
          PinnedEnvironment.sanitize_sql(["WHEN :id THEN :position", { id: env.id, position: env.position }])
        end

        reorder_query = "position = CASE id #{cases.join(" ")} END"

        PinnedEnvironment.where(id: pinned_environments.map(&:id)).update_all(reorder_query)

        {
          environment: environment.reload,
          errors: [],
        }
      end
    end
  end
end
