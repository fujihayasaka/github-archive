# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module CommentPositions
      class IndeterminateComment < Platform::Objects::Base
        description "Indeterminate positioning for a review comment"
        feature_flag :graphql_pr_comment_positioning

        field :reason, Enums::PullRequestReviewCommentIndeterminatePositionError, "Reason behind not providing the positional data"
        def reason
          object[:position].reason
        end

        # Determine whether the viewer can access this object via the API (called internally).
        # This is where Egress checks for OAuth scopes and GitHub Apps go.
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_api_can_access?(permission, _object)
          true # rubocop:disable GitHub/GraphqlApiAuthorization
        end

        # Determine whether the viewer can see this object (called internally).
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_viewer_can_see?(permission, object)
          true # rubocop:disable GitHub/GraphqlApiAuthorization
        end
      end
    end
  end
end
