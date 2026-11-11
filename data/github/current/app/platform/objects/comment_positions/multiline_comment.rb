# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module CommentPositions
      class MultilineComment < Platform::Objects::Base
        docs_category :issues
        description "Positioning attributes for a multi-line level comment"
        feature_flag :graphql_pr_comment_positioning

        field :start_path, String, "Initial file path the review comment has been made on"
        def start_path = object[:position].start_path

        field :start_line, Integer, "Line number the review comment started at. The first line of a file is line one"
        def start_line = object[:position].start_line

        field :start_commit_oid, String, "Commit identifier where the start line of the review comment has been made on"
        def start_commit_oid = object[:position].start_commit_oid

        field :end_path, String, "Eventual file path the review comment has been made on"
        def end_path = object[:position].end_path

        field :end_line, Integer, "Line number the review comment ended at"
        def end_line = object[:position].end_line

        field :end_commit_oid, String, "Commit identifier where the end line of the review comment has been made on"
        def end_commit_oid = object[:position].end_commit_oid

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
