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

      field :state_reason, Enums::IssueStateReason, "The reason the issue state was changed to closed.", null: true do
        argument :enable_duplicate, Boolean, "Whether or not to return state reason for duplicates", required: false, default_value: false, visibility: :internal do
          deprecated(
            start_date: Date.new(2025, 6, 13),
            reason: "The state reason for duplicate issue is now returned by default.",
            superseded_by: nil,
            owner: "issues",
          )
        end
      end

      field :closing_project_item_status, String, "The status column value that triggered the auto-close project workflow for this event", null: true, visibility: :under_development

      field :duplicate_of, Unions::IssueOrPullRequest, "The issue or pull request that this issue was marked as a duplicate of.", null: true

      def state_reason(enable_duplicate: false)
        @object.state_reason || PlatformTypes::IssueStateReason::COMPLETED.downcase
      end

      def closer
        @object.async_visible_closer(@context[:permission])
      end

      def closing_project_item_status
        @object.column_name
      end

      def duplicate_of
        return Promise.resolve(nil) unless @object.state_reason&.downcase == PlatformTypes::IssueStateReason::DUPLICATE.downcase

        @object.async_issue_event_detail.then do |event_detail|
          event_detail.async_subject.then do |reference|
            next nil unless reference
            next nil unless reference.is_a?(::Issue)
            next nil unless context[:cap_filter].authorized_resources([reference]).any?
            reference.async_visible_and_readable_by?(@context[:viewer]).then do |can_read|
              next nil unless can_read
              next reference
            end
          end
        end
      end

      url_fields description: "The HTTP URL for this closed event." do |event|
        event.async_path_uri
      end
    end
  end
end
