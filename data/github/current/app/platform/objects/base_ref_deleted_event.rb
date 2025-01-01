# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class BaseRefDeletedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'base_ref_deleted' event on a given pull request."

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rbrde, :repo_id, :issue_id, :base_ref_deleted_event_id]
      ], as: "BRDE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rbrde,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          base_ref_deleted_event_id: event.id,
        }
      end
      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, base_ref_deleted_event)
        permission.belongs_to_issue_event(base_ref_deleted_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: true
      field :base_ref_name, String, description: "Identifies the name of the Ref associated with the `base_ref_deleted` event.", null: true

      def base_ref_name
        @object.async_issue.then do |issue|
          issue.async_pull_request.then do |pull_request|
            pull_request.base_ref.force_encoding("utf-8")
          end
        end
      end
    end
  end
end
