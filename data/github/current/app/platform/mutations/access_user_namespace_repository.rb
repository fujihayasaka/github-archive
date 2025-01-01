# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class AccessUserNamespaceRepository < Platform::Mutations::Base

      description "Access user namespace repository for a temporary duration."

      minimum_accepted_scopes ["admin:enterprise"]

      argument :enterprise_id, ID, "The ID of the enterprise owning the user namespace repository.", required: true, loads: Objects::Enterprise
      argument :repository_id, ID, "The ID of the user namespace repository to access.", required: true

      field :repository, Objects::Repository, "The repository that is temporarily accessible.", null: true
      field :expires_at, Scalars::DateTime, "The time that repository access expires at", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, enterprise:, **inputs)
        permission.access_allowed?(
          :manage_user_namespace_repositories,
          resource: enterprise,
          repo: nil,
          organization: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false
        )
      end

      def resolve(enterprise:, repository_id:, **inputs)
        user = context[:viewer]
        ensure_business_can_use_api!(enterprise)

        unless enterprise.allow_unlock_user_namespace_repositories? && enterprise.feature_enabled?(:emu_user_namespace_repositories_api)
          raise Platform::Errors::Forbidden.new("Accessing user namespace repositories is not available for this business.")
        end

        # This repository must be loaded with the security violation behaviour set to :allow, because the viewer does
        # not have access to the repository yet.
        _, repo_id = Platform::Helpers::NodeIdentification.from_global_id(repository_id)
        Loaders::ActiveRecord.load(::Repository, repo_id, security_violation_behaviour: :allow).then do |repository|
          ## Should this be 404 instead?
          unless user.can_unlock_user_repo?(repository: repository)
            raise Errors::Forbidden.new("#{context[:viewer].display_login} is not authorized to unlock this repository")
          end

          repo_unlock = user.unlock_repository(repository)
          unless repo_unlock
            raise Errors::Unprocessable.new("This repository could not be accessed")
          end

          {
            repository: repository,
            expires_at: repo_unlock.expires_at
          }
        end
      end
    end
  end
end
