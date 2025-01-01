# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UserNamespaceRepository < Platform::Objects::Base
      description "A repository owned by an Enterprise Managed user."

      implements_node templates: [[:ri, :user_namespace_repository_id]], as: "UNR", ready_date: Platform::Helpers::GlobalId::COHORT_5 do |user_namespace_repo|
        user_namespace_repo.then do |repo|
          {
            prefix: :unr,
            user_namespace_repository_id: repo.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, repository)
        return false unless permission.viewer&.is_enterprise_managed?

        repository.async_owner.then do |repo_owner|
          next false unless repo_owner.is_a?(::User)

          repo_owner.async_enterprise_managed_business.then do |business|
            permission.access_allowed?(
              :read_user_namespace_repositories,
              resource: business,
              repo: nil,
              organization: nil,
              allow_integrations: false,
              allow_user_via_granular_actor: false
            )
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, repository)
        permission.viewer&.can_unlock_user_repo?(repository: repository)
      end

      minimum_accepted_scopes ["admin:enterprise"]

      field :name, String, "The name of the repository.", null: false
      field :owner, Interfaces::RepositoryOwner, method: :async_owner, description: "The user owner of the repository.", null: false
      field :name_with_owner, String, description: "The repository's name with owner.", null: false, resolver_method: :async_name_with_owner_for_api

      def async_name_with_owner_for_api
        @object.async_owner.then do
          @object.name_with_owner_for_api(use: context[:serialize_login])
        end
      end
    end
  end
end
