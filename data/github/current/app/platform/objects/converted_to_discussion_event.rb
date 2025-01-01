# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ConvertedToDiscussionEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'converted_to_discussion' event on a given issue."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, converted_event)
        permission.belongs_to_issue_event(converted_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:citde, :repo_id, :issue_id, :converted_to_discussion_event_id]
      ], as: "CITDE", ready_date: "2021-10-11" do |event|
        {
          prefix: :citde,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          converted_to_discussion_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp

      field :discussion,
        Objects::Discussion,
        description: "The discussion that the issue was converted into.",
        null: true

      def discussion
        @object.async_repository.then do |repo|
          repo.async_discussions_on?.then do |discussions_on|
            discussions_on ? @object.async_subject : nil
          end
        end
      end
    end
  end
end
