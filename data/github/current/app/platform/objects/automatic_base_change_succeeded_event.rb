# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class AutomaticBaseChangeSucceededEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'automatic_base_change_succeeded' event on a given pull request."

      def self.async_api_can_access?(permission, event)
        permission.belongs_to_issue_event(event)
      end

      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rabcse, :repo_id, :issue_id, :automatic_base_change_succeeded_event_id]
      ], as: "ABCSE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rabcse,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          automatic_base_change_succeeded_event_id: event.id,
        }
      end
      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp


      field :pull_request, Objects::PullRequest, "PullRequest referenced by event.", method: :async_issue_or_pull_request, null: false

      field :old_base, String, "The old base for this PR", null: false
      def old_base
        @object.async_issue_event_detail.then do |detail|
          detail.title_was
        end
      end

      field :new_base, String, "The new base for this PR", null: false
      def new_base
        @object.async_issue_event_detail.then do |detail|
          detail.title_is
        end
      end

      url_fields description: "The HTTP URL for this event.", visibility: :internal do |event|
        event.async_path_uri
      end
    end
  end
end
