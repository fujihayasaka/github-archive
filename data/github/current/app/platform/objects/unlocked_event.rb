# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UnlockedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents an 'unlocked' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, unlocked_event)
        permission.belongs_to_issue_event(unlocked_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:ru, :repo_id, :issue_id, :id]
      ], as: "UNLOE", ready_date: Platform::Helpers::GlobalId::COHORT_1, allow_nil_for: [:issue_id] do |event|
        {
          prefix: :ru,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :lockable, Interfaces::Lockable, "Object that was unlocked.", method: :async_issue_or_pull_request, null: false
    end
  end
end
