# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class TransferredEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'transferred' event on a given issue or pull request."

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
        [:rt, :repo_id, :issue_id, :id]
      ], as: "TRE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rt,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :issue, Objects::Issue, "Identifies the issue associated with the event.", method: :async_issue, null: false
      field :from_repository, Objects::Repository, "The repository this came from", null: true
      def from_repository
        Loaders::ActiveRecord.load(::Repository, @object.subject_id, security_violation_behaviour: :nil)
      end
    end
  end
end
