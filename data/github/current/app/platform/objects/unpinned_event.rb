# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UnpinnedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents an 'unpinned' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, event)
        permission.belongs_to_issue_event(event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(abilities, object)
        abilities.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rue, :repo_id, :issue_id, :unpinned_event_id]
      ], as: "UNPE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rue,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          unpinned_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :issue, Objects::Issue, "Identifies the issue associated with the event.", method: :async_issue, null: false
    end
  end
end
