# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class PullRequestSummaryDelta < Platform::Objects::Base
      implements Platform::Interfaces::DiffDelta

      description "Represents the summarized changes to an individual file in a pull request, not including its text."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        permission.typed_can_access?("PullRequest", object.pull)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("PullRequest", object.pull)
      end

      minimum_accepted_scopes ["repo"]

      field :unresolved_comment_count, Integer, description: "The number of unresolved threads on this file.", null: false

      field :total_comments_count, Integer, description: "The number of total comments on this file.", null: false

      field :total_annotations_count, Integer, description: "The number of total annotations on this file", null: false

      def unresolved_comment_count
        @object.unresolved_comment_count
      end

      field :viewer_viewed_state, Enums::FileViewedState, description: "Whether the authenticated viewer has viewed this file in the given Pull Request", null: true, visibility: :internal

      field :path_ownership, Objects::PathOwnership, null: false, description: "The owners for the patch's file path.", visibility: :internal
    end
  end
end
