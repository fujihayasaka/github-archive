# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module CommentPositions
      class FileComment < Platform::Objects::Base
        description "Positioning attributes for a file level comment"
        feature_flag :graphql_pr_comment_positioning

        field :path, String, "File path the review comment has been made on"
        def path
          object[:position].path
        end

        field :commit_oid, String, "Commit identifier the review comment has been made on"
        def commit_oid
          object[:position].commit_oid
        end

        # Determine whether the viewer can access this object via the API (called internally).
        # This is where Egress checks for OAuth scopes and GitHub Apps go.
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_api_can_access?(permission, object)
          positionable = object[:positionable]

          case positionable.class.name
          when "PullRequestReviewThread"
            permission.typed_can_access?("PullRequestReviewThread", positionable)
          end
        end

        # Determine whether the viewer can see this object (called internally).
        # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
        def self.async_viewer_can_see?(permission, object)
          positionable = object[:positionable]

          case positionable.class.name
          when "PullRequestReviewThread"
            permission.typed_can_see?("PullRequestReviewThread", positionable)
          end
        end
      end
    end
  end
end
