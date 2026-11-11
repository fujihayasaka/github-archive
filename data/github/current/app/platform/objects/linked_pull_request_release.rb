# typed: strict
# frozen_string_literal: true

module Platform
  module Objects
    # Pairs a merged pull request with its earliest release.
    # Used by the issue sidebar (stable preferred over pre-release).
    class LinkedPullRequestRelease < Platform::Objects::Base
      docs_category :pulls
      visibility :internal
      description "A linked pull request paired with its earliest release."
      minimum_accepted_scopes ["repo"]

      sig { params(permission: T.untyped, object: T.untyped).returns(T.untyped) }
      def self.async_api_can_access?(permission, object)
        permission.hidden_from_public?(self)
      end

      sig { params(permission: T.untyped, object: T.untyped).returns(T.untyped) }
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("PullRequest", object.pull_request)
      end

      field :pull_request, Objects::PullRequest,
        null: true, # nullable as defense-in-depth; node is filtered by async_viewer_can_see? before this resolves
        description: "The merged pull request.",
        visibility: :internal

      field :release, Objects::Release,
        null: false,
        description: "The earliest release containing this pull request's merge commit. Stable releases are preferred over pre-releases.",
        visibility: :internal
    end
  end
end
