# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class ClosedEvent < Platform::Objects::Base
      model_name "IssueEvent"
      description "Represents a 'closed' event on any `Closable`."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, closed_event)
        permission.belongs_to_issue_event(closed_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.belongs_to_issue(object)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:rce, :repo_id, :issue_id, :closed_event_id]], as: "CE", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |event|
        Timeline::Placeholder.async_value_for(event).then do |event|
          {
            prefix: :rce,
            repo_id: event.repository_id,
            issue_id: event.issue_id,
            closed_event_id: event.id,
          }
        end
      end

      implements Interfaces::TimelineEvent

      implements Interfaces::PerformableViaApp

      implements Interfaces::UniformResourceLocatable


      field :closable, Interfaces::Closable, "Object that was closed.", method: :async_issue_or_pull_request, null: false

      field :closer, Unions::Closer, "Object which triggered the creation of this event.", null: true

      field :state_reason, Enums::IssueStateReason, "The reason the issue state was changed to closed.", null: true

      field :closing_project_item_status, String, "The status column value that triggered the auto-close project workflow for this event", null: true, visibility: :under_development

      def state_reason
        @object.state_reason || PlatformTypes::IssueStateReason::COMPLETED.downcase
      end

      def closer
        @object.async_visible_closer(@context[:permission])
      end

      def closing_project_item_status
        @object.column_name
      end

      url_fields description: "The HTTP URL for this closed event." do |event|
        event.async_path_uri
      end
    end
  end
end
