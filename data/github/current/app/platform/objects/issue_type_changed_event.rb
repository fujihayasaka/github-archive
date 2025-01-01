# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueTypeChangedEvent < Platform::Objects::Base
      description "Represents a 'issue_type_changed' event on a given issue."
      model_name "IssueEvent"

      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp

      scopeless_tokens_as_minimum

      field :issue_type, Objects::IssueType, "The issue type added.", null: true

      def issue_type
        @object.async_issue.then do |issue|
          @context[:permission].async_repo_and_org_owner(issue).then do |_, owner|
            next unless T.must(owner).issue_types_enabled?
            @object.async_issue_type.then do |issue_type|
              next unless issue_type.enabled?
              Platform::Models::IssueTypeWithContext.new(issue_type, issue:)
            end
          end
        end
      end

      field :prev_issue_type, Objects::IssueType, "The issue type removed.", null: true

      def prev_issue_type
        @object.async_issue.then do |issue|
          @context[:permission].async_repo_and_org_owner(issue).then do |_, owner|
            next unless T.must(owner).issue_types_enabled?
            @object.async_prev_issue_type.then do |issue_type|
              next unless issue_type.enabled?
              Platform::Models::IssueTypeWithContext.new(issue_type, issue:)
            end
          end
        end
      end

      implements_node templates: [[:ritce, :repo_id, :issue_id, :id]],
        as: "ITCE",
        ready_date: "1970-01-01" do |event|
        Timeline::Placeholder.async_value_for(event).then do |event|
          {
            prefix: :ritce,
            repo_id: event.repository_id,
            issue_id: event.issue_id,
            id: event.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, issue_event: ::IssueEvent).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_api_can_access?(permission, issue_event)
        permission.belongs_to_issue_event(issue_event)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      sig { params(permission: T.untyped, issue_event: ::IssueEvent).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_viewer_can_see?(permission, issue_event)
        permission.belongs_to_issue(issue_event).then do |issue_event_accessible|
          next false unless issue_event_accessible

          issue_event.async_issue.then do |issue|
            if cap_filter = permission.cap_filter
              next false unless cap_filter.authorized_resources([issue]).any?
            end

            true
          end
        end
      end
    end
  end
end
