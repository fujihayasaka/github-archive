# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AddedToMergeQueueEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents an 'added_to_merge_queue' event on a given pull request."
      visibility :public, environments: [:dotcom, :enterprise]

      def self.async_api_can_access?(permission, event)
        permission.belongs_to_issue_event(event)
      end

      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:amqe, :repo_id, :issue_id, :id]
      ], as: "ATMQE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :amqe,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          id: event.id,
        }
      end
      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp

      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: true
      field :enqueuer, Objects::User, "The user who added this Pull Request to the merge queue", method: :async_actor, null: true
      field :merge_queue, Objects::MergeQueue,
        description: "The merge queue where this pull request was added to.",
        null: true

      def merge_queue
        @object.async_issue_or_pull_request.then do |pr_or_issue|
          next unless pr_or_issue.is_a?(::PullRequest)
          @object.async_repository.then do |repo|
            repo.merge_queue_for(branch: pr_or_issue.base_ref_name)
          end
        end
      end

      url_fields description: "The HTTP URL for this event.", visibility: :internal do |event|
        event.async_path_uri
      end
    end
  end
end
