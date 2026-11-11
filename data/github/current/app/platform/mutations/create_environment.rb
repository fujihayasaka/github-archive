# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateEnvironment < Platform::Mutations::Base
      description "Creates an environment or simply returns it if already exists."

      minimum_accepted_scopes ["public_repo"]

      argument :repository_id, ID, "The node ID of the repository.", required: true, loads: Objects::Repository, as: :repo
      argument :name, String, "The name of the environment.", required: true

      resolve_tenant_context do |repo:, **_|
        _, repo_id = Platform::Helpers::NodeIdentification.from_global_id(repo)
        Repositories::Public.resolve_tenant(id: repo_id)
      end

      error_fields
      field :environment, Objects::Environment, "The new or existing environment.", null: true

      # This mutation can safely read arguments from replicas
      read_arguments_from_replicas!

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repo:, **inputs)
        # We need to make the launch app to be able to call this API without any specific scope.
        return true if permission.target == :internal

        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:write_actions_environments_repo,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        end
      end

      def resolve(repo:, name:, **inputs)
        begin
          env = Environment.create_for_repository(repo.id, name)
        rescue ActiveRecord::StatementInvalid
          raise Platform::Errors::Validation.new("Unable to create Environment with name '#{name}'")
        end

        raise Platform::Errors::Validation.new("Unable to create Environment with name '#{name}'") if env.nil? || !env.valid?

        { environment: env, errors: [] }
      end
    end
  end
end
