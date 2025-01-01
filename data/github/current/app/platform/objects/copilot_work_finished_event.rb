# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotWorkFinishedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'copilot_work_finished' event on a given pull request."
      required_capabilities [:mobile_only_schema_mask, :copilot_timeline_events]

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, work_finished_event)
        permission.belongs_to_issue_event(work_finished_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rcwfe, :repo_id, :issue_id, :copilot_work_finished_event_id]
      ], as: "CWFE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rcwfe,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          copilot_work_finished_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp

      implements Interfaces::UniformResourceLocatable


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      url_fields description: "The HTTP URL for this Copilot work finished event." do |event|
        event.async_path_uri
      end
    end
  end
end
