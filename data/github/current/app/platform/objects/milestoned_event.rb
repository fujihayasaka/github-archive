# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MilestonedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'milestoned' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, milestoned_event)
        permission.belongs_to_issue_event(milestoned_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rme, :repo_id, :issue_id, :milestoned_event_id]
      ], as: "MIE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rme,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          milestoned_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :subject, Unions::MilestoneItem, "Object referenced by event.", method: :async_issue_or_pull_request, null: false

      field :milestone_title, String, "Identifies the milestone title associated with the 'milestoned' event.", method: :async_milestone_title, null: false

      field :milestone, Milestone, "The milestone associated with this event.", visibility: :internal, method: :async_milestone, null: true
    end
  end
end
