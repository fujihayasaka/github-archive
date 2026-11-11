# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueFieldRemovedEvent < Platform::Objects::Base
      description "Represents a 'issue_field_removed' event on a given issue."
      model_name "IssueEvent"

      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp

      scopeless_tokens_as_minimum
      feature_flag :issue_fields_timeline_events

      field :issue_field, Unions::IssueFields, "The issue field removed.", null: true

      def issue_field
        @object.async_issue.then do |issue|
          @context[:permission].async_repo_and_org_owner(issue).then do |repo, _owner|
            next nil unless repo && IssueFieldsFeature.enabled?(repo, actor: @context[:viewer])

            async_issue_field_event_detail.then do |detail|
              next nil unless detail
              async_issue_field_event_visible_for_viewer(detail).then do |visible|
                next nil unless visible

                Platform::Loaders::ActiveRecord.load(::IssueField, detail.issue_field_id).then do |issue_field|
                  Platform::Models::IssueFieldWithIssueContext.new(issue_field, issue: issue) if issue_field
                end
              end
            end
          end
        end
      end

      implements_node templates: [[:rifre, :repo_id, :issue_id, :id]],
        as: "IFRE",
        ready_date: "1970-01-01" do |event|
        Timeline::Placeholder.async_value_for(event).then do |event|
          {
            prefix: :rifre,
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

            issue_event.async_issue_event_detail.then do |detail|
              next false unless detail&.issue_field_id
              Platform::Loaders::ActiveRecord.load(::IssueField, detail.issue_field_id).then do |issue_field|
                next false unless issue_field
                ::ActiveRecord::Associations::Preloader.new(records: [issue_field], associations: :owner).call

                viewable = issue_field.viewable_by?(viewer: permission.viewer, repository_id: issue&.repository_id)
                next false unless viewable

                wrapped = Platform::Models::IssueFieldWithIssueContext.new(issue_field, issue: issue)
                permission.typed_can_access?(issue_field.class.name, wrapped).then do |can_access_issue_field|
                  can_access_issue_field
                end
              end
            end
          end
        end
      end

      private

      def async_issue_field_event_detail
        @object.async_issue_event_detail.then do |detail|
          next nil unless detail&.issue_field_id
          detail
        end
      end

      def async_issue_field_event_visible_for_viewer(detail)
        return Promise.resolve(false) unless detail&.issue_field_id

        Platform::Loaders::IssueFieldEventVisibleCheck.load(@context[:viewer], @object.id)
      end
    end
  end
end
