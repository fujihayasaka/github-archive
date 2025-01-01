# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BaseRefChangedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'base_ref_changed' event on a given issue or pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, base_ref_changed_event)
        permission.belongs_to_issue_event(base_ref_changed_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rbrce, :repo_id, :issue_id, :base_ref_changed_event_id]
      ], as: "BRCE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rbrce,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          base_ref_changed_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      field :previous_ref_name, String, "Identifies the name of the base ref for the pull request before it was changed.", method: :async_title_was, null: false

      field :current_ref_name, String, "Identifies the name of the base ref for the pull request after it was changed.", method: :async_title_is, null: false

      # TODO: remove this when the declaration in TimelineEvent becomes public
      database_id_field
    end
  end
end
