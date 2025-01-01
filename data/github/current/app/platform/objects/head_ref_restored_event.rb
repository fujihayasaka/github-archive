# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class HeadRefRestoredEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'head_ref_restored' event on a given pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, head_ref_restored_event)
        permission.belongs_to_issue_event(head_ref_restored_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rhrre, :repo_id, :issue_id, :head_ref_restored_event_id]
      ], as: "HRRE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rhrre,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          head_ref_restored_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false
    end
  end
end
