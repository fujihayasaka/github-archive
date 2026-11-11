# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Environment < Platform::Objects::Base
      description "An environment."

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

      implements_node templates: [[:en, :repo_id, :environment_id]], as: "EN", ready_date: Platform::Helpers::GlobalId::COHORT_2 do |environment|
        environment.async_repository.then do |repo|
          raise Platform::Errors::NotFound, "Repository not found for the given environment: #{environment.id}" if repo.nil?
          {
            prefix: :en,
            repo_id: repo.id,
            environment_id: environment.id
          }
        end
      end

      database_id_field

      field :name, String, description: "The name of the environment", null: false

      field :gates, Connections.define(Objects::Gate), description: "The gates defined for this environment", connection: true, numeric_pagination_enabled: true, null: false, visibility: :internal

      field :is_pinned, Boolean, description: "Indicates whether or not this environment is currently pinned to the repository", null: true

      field :pinned_position, Integer, description: "The position of the environment if it is pinned, null if it is not pinned", null: true

      field :latest_completed_deployment, Objects::Deployment, description: "The latest completed deployment with status success, failure, or error if it exists", null: true

      def is_pinned
        @object.async_pinned_environment.then do
          @object.is_pinned?
        end
      end

      def pinned_position
        @object.async_pinned_environment.then do |pinned|
          pinned.position if pinned
        end
      end

      def latest_completed_deployment
        @object.latest_completed_deployment
      end

      def gates(**arguments)
        @object.async_repository.then do |repo|
          repo.async_owner.then do |_owner|
            if repo.can_use_environments?
              @object.gates.scoped
            else
              ::Gate.none
            end
          end
        end
      end

      field :protection_rules, Connections.define(Objects::DeploymentProtectionRule), description: "The protection rules defined for this environment", connection: true, numeric_pagination_enabled: true, null: false, method: :gates
    end
  end
end
