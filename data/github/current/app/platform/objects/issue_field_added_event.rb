# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldAddedEvent < Platform::Objects::Base
      description "Represents a 'issue_field_added' event on a given issue."
      model_name "IssueEvent"

      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp

      scopeless_tokens_as_minimum
      feature_flag :issue_fields_timeline_events

      field :issue_field, Unions::IssueFields, "The issue field added.", null: true
      field :value, String, "The value of the added field.", null: true
      field :color, String, "The color if it is a single-select field.", null: true

      def issue_field
        @object.async_issue.then do |issue|
          @context[:permission].async_repo_and_org_owner(issue).then do |repo, _owner|
            next unless repo && IssueFieldsFeature.enabled?(repo, actor: @context[:viewer])
            @object.async_issue_event_detail.then do |detail|
              if detail.issue_field_id
                Platform::Loaders::ActiveRecord.load(::IssueField, detail.issue_field_id).then do |issue_field|
                  Platform::Models::IssueFieldWithIssueContext.new(issue_field, issue: issue) if issue_field
                end
              end
            end
          end
        end
      end

      def value
        @object.async_issue_event_detail.then do |detail|
          detail.issue_field_value
        end
      end

      def color
        @object.async_issue_event_detail.then do |detail|
          color_number = detail.issue_field_value_color
          return nil unless color_number

          # Find the color string from the COLORS mapping in IssueFieldOption
          color_key = ::IssueFieldOption::COLORS.key(color_number)
          color_key&.to_s&.upcase
        end
      end

      implements_node templates: [[:rifae, :repo_id, :issue_id, :id]],
        as: "IFAE",
        ready_date: "1970-01-01" do |event|
        Timeline::Placeholder.async_value_for(event).then do |event|
          {
            prefix: :rifae,
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
