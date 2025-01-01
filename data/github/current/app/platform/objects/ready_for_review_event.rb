# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ReadyForReviewEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'ready_for_review' event on a given pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, merged_event)
        permission.belongs_to_issue_event(merged_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rrfre, :repo_id, :issue_id, :ready_for_review_event_id]
      ], as: "RFRE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rrfre,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          ready_for_review_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp

      implements Interfaces::UniformResourceLocatable


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      url_fields description: "The HTTP URL for this ready for review event." do |event|
        event.async_path_uri
      end
    end
  end
end
