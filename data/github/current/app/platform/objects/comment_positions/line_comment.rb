# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module CommentPositions
      class LineComment < Platform::Objects::Base
        docs_category :issues
        description "Positioning attributes for a comment made on a line of code in a pull request"
        feature_flag :graphql_pr_comment_positioning

        field :path, String, "File path the review comment has been made on"
        def path = object[:position].path

        field :commit_oid, String, "Commit identifier where the review comment has been made on"
        def commit_oid = object[:position].commit_oid

        field :line, Integer, "Line number the review comment is on. The first line of a file is line one"
        def line = object[:position].line

        field :base_commit_oid, String, "Base commit identifier (left side of the diff) the review comment position was computed against"
        def base_commit_oid = object[:position].base_commit_oid

        field :head_commit_oid, String, "Head commit identifier (right side of the diff) the review comment position was computed against"
        def head_commit_oid = object[:position].head_commit_oid

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
