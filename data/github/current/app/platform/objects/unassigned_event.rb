# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class UnassignedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents an 'unassigned' event on any assignable object."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, unassigned_event)
        permission.belongs_to_issue_event(unassigned_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rue, :repo_id, :issue_id, :unassigned_event_id]
      ], as: "UNE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rue,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          unassigned_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      # The subject and actor are swapped for unassignment and assignment events
      def actor
        object.async_subject.then do |actor|
          actor || ::User.ghost
        end
      end

      def safe_actor
        object.async_subject.then do |actor|
          actor || ::User.ghost
        end
      end

      field :assignable, Interfaces::Assignable, "Identifies the assignable associated with the event.", method: :async_issue_or_pull_request, null: false

      field :user, Objects::User, description: "Identifies the subject (user) who was unassigned.", method: :async_actor, null: true do
        deprecated(
          start_date: Date.new(2019, 9, 1),
          reason: "Assignees can now be mannequins.",
          superseded_by: "Use the `assignee` field instead.",
          owner: "tambling",
        )
      end

      field :assignee, Unions::Assignee, description: "Identifies the user or mannequin that was unassigned.", method: :async_actor, null: true
    end
  end
end
