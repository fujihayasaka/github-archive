# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MentionedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'mentioned' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, mentioned_event)
        permission.belongs_to_issue_event(mentioned_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rm, :repo_id, :issue_id, :id]
      ], as: "MEE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rm,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      # TODO: remove this when the declaration in TimelineEvent becomes public
      database_id_field
    end
  end
end
