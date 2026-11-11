# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class RenamedTitleEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'renamed' event on a given issue or pull request"

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, renamed_title_event)
        permission.belongs_to_issue_event(renamed_title_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [
        [:rrte, :repo_id, :issue_id, :renamed_title_event_id]
      ], as: "RTE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        {
          prefix: :rrte,
          repo_id: event.repository_id,
          issue_id: event.issue_id,
          renamed_title_event_id: event.id,
        }
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp


      field :subject, Unions::RenamedTitleSubject, "Subject that was renamed.", method: :async_issue_or_pull_request, null: false

      field :current_title, String, "Identifies the current title of the issue or pull request.", null: false

      def current_title
        @object.async_issue_event_detail.then do |issue_event_detail|
          # addresses a corner case where an issue event exists, but the title is nil
          # returning an empty string allows the view to load without triggering a server error
          issue_event_detail.title_is || ""
        end
      end

      field :previous_title, String, "Identifies the previous title of the issue or pull request.", null: false

      def previous_title
        @object.async_issue_event_detail.then do |issue_event_detail|
          issue_event_detail.title_was || ""
        end
      end
    end
  end
end
