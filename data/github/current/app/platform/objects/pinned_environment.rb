# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PinnedEnvironment < Platform::Objects::Base
      description "Represents a pinned environment on a given repository"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, environment)
        permission.async_repo_and_org_owner(environment).then do |repo, org|
          permission.access_allowed?(:read_actions, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, environment)
        permission.load_repo_and_owner(environment).then do |repo|
          repo.resources.actions.async_readable_by?(permission.viewer)
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:pen, :repo_id, :environment_id, :id]
      ], as: "PEN", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |pinned_environment|
        {
          prefix: :pen,
          repo_id: pinned_environment.repository_id,
          environment_id: pinned_environment.environment_id,
          id: pinned_environment.id,
        }
      end

      database_id_field

      field :repository, Objects::Repository, description: "The repository that this environment was pinned to.", method: :async_repository, null: false
      field :environment, Objects::Environment, "Identifies the environment associated.", method: :async_environment, null: false
      field :position, Integer, "Identifies the position of the pinned environment.", null: false
      field :created_at, Scalars::DateTime, "Identifies the date and time when the pinned environment was created", null: false
    end
  end
end
