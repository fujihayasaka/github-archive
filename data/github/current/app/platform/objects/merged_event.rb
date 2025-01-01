# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MergedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'merged' event on a given pull request."

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
        [:rme, :repo_id, :issue_id, :merged_event_id]
      ], as: "ME", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rme,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          merged_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp

      implements Interfaces::UniformResourceLocatable


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      field :commit, Objects::Commit, description: "Identifies the commit associated with the `merge` event.", null: true

      def commit
        @object.async_repository.then do |repository|
          Loaders::GitObject.load(repository, @object.commit_id, expected_type: :commit)
        end
      end

      field :merge_ref_name, String, description: "Identifies the name of the Ref associated with the `merge` event.", null: false

      def merge_ref_name
        @object.async_issue.then do |issue|
          issue.async_pull_request.then do |pull_request|
            pull_request.base_ref.force_encoding("utf-8")
          end
        end
      end

      field :merge_ref, Ref, description: "Identifies the Ref associated with the `merge` event.", null: true

      def merge_ref
        pull_request_promise = Loaders::ActiveRecord.load(::Issue, @object.issue_id).then do |issue|
          Loaders::ActiveRecord.load(::PullRequest, T.must(issue).pull_request_id)
        end

        repository_promise = Loaders::ActiveRecord.load(::Repository, @object.repository_id)

        Promise.all([pull_request_promise, repository_promise]).then do |(pull_request, repository)|
          repository.async_network.then do
            repository.heads.find(pull_request.base_ref)
          end
        end
      end

      # TODO leave this as internal until PullRequest#async_pushable_repo_for is fully batched.
      field :viewer_can_revert, Boolean, visibility: :internal, description: "Check if the current user can revert this merge commit.", null: false

      def viewer_can_revert
        @object.async_revertable_by?(@context[:viewer])
      end

      url_fields description: "The HTTP URL for this merged event." do |event|
        event.async_path_uri
      end

      field :via_merge_queue, Boolean, visibility: :internal, description: "Check if the event was the result of the merge queue", null: false

      def via_merge_queue
        %w(merge_queue merge_queue_merge api_merge_queue_merge).include?(@object.message)
      end

      field :via_merge_queue_a_p_i, Boolean, visibility: :internal, description: "Check if the event was the result of the merge queue API", null: false

      def via_merge_queue_a_p_i
        @object.message == "api_merge_queue_merge"
      end
    end
  end
end
