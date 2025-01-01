# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReopenedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'reopened' event on any `Closable`."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, reopened_event)
        permission.belongs_to_issue_event(reopened_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rre, :repo_id, :issue_id, :reopened_event_id]
      ], as: "REE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rre,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          reopened_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :closable, Interfaces::Closable, "Object that was reopened.", method: :async_issue_or_pull_request, null: false

      field :state_reason, Enums::IssueStateReason, "The reason the issue state was changed to open.",
        null: true
    end
  end
end
