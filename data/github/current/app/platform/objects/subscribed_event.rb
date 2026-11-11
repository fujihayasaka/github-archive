# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SubscribedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'subscribed' event on a given `Subscribable`."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, subscribed_event)
        permission.belongs_to_issue_event(subscribed_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rse, :repo_id, :issue_id, :subscribed_event_id]
      ], as: "SE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rse,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          subscribed_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :subscribable, Interfaces::Subscribable, "Object referenced by event.", method: :async_issue_or_pull_request, null: false
    end
  end
end
