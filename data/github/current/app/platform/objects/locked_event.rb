# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class LockedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'locked' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, locked_event)
        permission.belongs_to_issue_event(locked_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rle, :repo_id, :issue_id, :locked_event_id]
      ], as: "LOE", ready_date: Platform::Helpers::GlobalId::COHORT_1, allow_nil_for: [:issue_id] do |event|
        {
          prefix: :rle,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          locked_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :lockable, Interfaces::Lockable, "Object that was locked.", method: :async_issue_or_pull_request, null: false

      field :lock_reason, Enums::LockReason, "Reason that the conversation was locked (optional).", null: true

      def lock_reason
        @object.async_issue_event_detail.then do |issue_event_detail|
          issue_event_detail.lock_reason
        end
      end
    end
  end
end
