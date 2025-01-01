# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RepositoriesUsingDependency < Platform::Objects::Base
      description "A collection of repositories by the same owner that use a " \
        "particular dependency."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, repos_using_dependency)
        repos_using_dependency.async_dependency.then do |repo|
          permission.typed_can_access?("Repository", repo)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, repos_using_dependency)
        repos_using_dependency.async_dependency.then do |repo|
          permission.typed_can_see?("Repository", repo)
        end
      end

      scopeless_tokens_as_minimum

      visibility :under_development, environments: [:dotcom]
      visibility :internal, environments: [:enterprise]

      field :owner, Interfaces::RepositoryOwner, method: :async_owner,
        description: "The user or organization who owns these repositories.", null: false

      field :dependency, Objects::Repository, method: :async_dependency,
        description: "The repository that the other repositories depend on. Not necessarily " \
          "owned by the owner of the other repositories.", null: false

      field :repositories, Connections.define(Objects::Repository), connection: true, null: false do
        description "The repositories, all owned by the same user or organization, that " \
          "rely on the dependency."
      end

      def repositories
        repos = @object.repositories(viewer: @context[:viewer])
        ArrayWrapper.new(repos)
      end
    end
  end
end
