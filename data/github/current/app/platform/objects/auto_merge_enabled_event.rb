# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AutoMergeEnabledEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'auto_merge_enabled' event on a given pull request."

      def self.async_api_can_access?(permission, event)
        permission.belongs_to_issue_event(event)
      end

      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:amee, :repo_id, :issue_id, :id]
      ], as: "AMEE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :amee,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          id: event.id,
        }
      end
      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: true
      field :enabler, Objects::User, "The user who enabled auto-merge for this Pull Request", method: :async_actor, null: true

      url_fields description: "The HTTP URL for this event.", visibility: :internal do |event|
        event.async_path_uri
      end
    end
  end
end
