# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CommentDeletedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'comment_deleted' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, comment_deleted_event)
        permission.belongs_to_issue_event(comment_deleted_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rcde, :repo_id, :issue_id, :comment_deleted_event_id]
      ], as: "CDE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rcde,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          comment_deleted_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      # TODO: remove this when the declaration in TimelineEvent becomes public
      database_id_field

      field :deleted_comment_author, Interfaces::Actor, description: "The user who authored the deleted comment.", null: true

      def deleted_comment_author
        @object.async_subject.then do |actor|
          actor unless actor&.hide_from_user?(@context[:viewer])
        end
      end
    end
  end
end
