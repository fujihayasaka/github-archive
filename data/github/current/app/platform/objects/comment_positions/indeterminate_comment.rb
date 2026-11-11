# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    module CommentPositions
      class IndeterminateComment < Platform::Objects::Base
        docs_category :issues
        description "Indeterminate positioning for a review comment"
        feature_flag :graphql_pr_comment_positioning

        field :reason, Enums::PullRequestReviewCommentIndeterminatePositionError, "Reason behind not providing the positional data"
        def reason
          case object[:position].reason&.to_sym
          when :outdated, :missing_positional_data
            :missing_positional_data
          when :cannot_resolve_path, :base_path_not_found, :head_path_not_found
            :cannot_resolve_path
          when :cannot_resolve_start_path
            :cannot_resolve_start_path
          when :cannot_resolve_end_path
            :cannot_resolve_end_path
          when :cannot_resolve_line
            :cannot_resolve_line
          when :cannot_resolve_start_line, :start_line_not_found
            :cannot_resolve_start_line
          when :cannot_resolve_end_line, :end_line_not_found
            :cannot_resolve_end_line
          when :cannot_resolve_position
            :cannot_resolve_position
          when :cannot_resolve_start_position
            :cannot_resolve_start_position
          when :cannot_resolve_start_commit_oid, :cannot_resolve_commit_range, :cannot_resolve_diff
            :cannot_resolve_commits
          when :diff_entry_too_big, :blob_contents_too_large
            :blob_contents_too_large
          when :cannot_reposition_line, :could_not_reposition
            :cannot_reposition_line
          else
            :unknown
          end
        end

        field :base_commit_oid, String, "Base commit identifier (left side of the diff) the review comment position was computed against"
        def base_commit_oid = object[:position].base_commit_oid

        field :head_commit_oid, String, "Head commit identifier (right side of the diff) the review comment position was computed against"
        def head_commit_oid = object[:position].head_commit_oid

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
