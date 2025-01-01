# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    class ContributingGuidelines < Platform::Objects::Base
      extend T::Sig

      description "The Contributing Guidelines for a repository."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, contributing: RepositoryContributingGuidelines).returns(T.any(Promise[TrueClass], Promise[T::Boolean])) }
      def self.async_api_can_access?(permission, contributing)
        repo = contributing.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:get_contributing, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, object: RepositoryContributingGuidelines).returns(T.any(Promise[TrueClass], Promise[T::Boolean])) }
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end

      scopeless_tokens_as_minimum

      field :body, String, "The body of the Contributing Guidelines.", null: true

      url_fields description: "The HTTP URL for the Contributing Guidelines.", null: true do |contributing|
        contributing.url
      end

      field :repository, Repository, "The Repository containing the Contributing Guidelines.", null: true, visibility: :internal


      sig { returns(T.nilable(::Repository)) }
      def repository
        @object = T.let(@object, T.nilable(RepositoryContributingGuidelines))
        @object.repository if !@object.nil? && @object.respond_to?(:repository)
      end
    end
  end
end
