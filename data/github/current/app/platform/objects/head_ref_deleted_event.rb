# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class HeadRefDeletedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'head_ref_deleted' event on a given pull request."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, head_ref_deleted_event)
        permission.belongs_to_issue_event(head_ref_deleted_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rhrde, :repo_id, :issue_id, :head_ref_deleted_event_id]
      ], as: "HRDE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rhrde,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          head_ref_deleted_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      field :head_ref_name, String, description: "Identifies the name of the Ref associated with the `head_ref_deleted` event.", null: false

      def head_ref_name
        @object.async_issue.then do |issue|
          issue.async_pull_request.then do |pull_request|
            pull_request.head_ref.force_encoding("utf-8")
          end
        end
      end

      field :head_ref, Ref, description: "Identifies the Ref associated with the `head_ref_deleted` event.", null: true

      def head_ref
        @object.async_issue.then do |issue|
          issue.async_pull_request.then do |pull_request|
            pull_request.async_head_repository.then do |repository|
              next unless repository

              repository.async_network.then do
                repository.heads.find(pull_request.head_ref)
              end
            end
          end
        end
      end
    end
  end
end
