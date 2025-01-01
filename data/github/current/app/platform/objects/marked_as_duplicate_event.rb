# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MarkedAsDuplicateEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'marked_as_duplicate' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, marked_as_duplicate_event)
        permission.belongs_to_issue_event(marked_as_duplicate_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object).then do |visible|
          next false unless visible
          object.async_subject_as_issue_or_pull_request.then do |canonical|
            next false unless canonical

            cap_filter = permission.cap_filter
            if cap_filter
              next false unless cap_filter.authorized_resources([canonical]).any?
            end

            graphql_type_name = Platform::Helpers::NodeIdentification.type_name_from_object(canonical)
            permission.typed_can_see?(graphql_type_name, canonical)
          end
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rmade, :repo_id, :issue_id, :id]
      ], as: "MADE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rmade,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp

      field :canonical, Unions::IssueOrPullRequest, "The authoritative issue or pull request which has been duplicated by another.", method: :async_issue_or_pull_request, null: true
      field :duplicate, Unions::IssueOrPullRequest, "The issue or pull request which has been marked as a duplicate of another.", method: :async_subject_as_issue_or_pull_request, null: true

      field :is_canonical_of_closed_duplicate, Boolean, "A boolean value that indicates whether this event corresponds to closing another issue as a duplicate of this one", null: true, visibility: :internal
      def is_canonical_of_closed_duplicate
        @object.async_issue_event_detail.then do |details|
          details&.state_reason&.downcase == "duplicate"
        end
      end

      field :is_cross_repository, Boolean, "Canonical and duplicate belong to different repositories.", method: :async_cross_subject_repository?, null: false

      url_fields prefix: :unmark_as_duplicate, description: "The HTTP URL to revert this duplicate mark event.", visibility: :internal do |event|
        event.async_unmark_as_duplicate_path_uri
      end

      field :viewer_can_undo, Boolean, visibility: :internal, description: "Check if the viewer can mark this issue or pull request as not a duplicate.", null: false

      def viewer_can_undo
        @object.async_can_be_undone_by?(@context[:viewer])
      end
    end
  end
end
