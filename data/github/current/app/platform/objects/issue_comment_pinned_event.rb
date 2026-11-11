# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class IssueCommentPinnedEvent < Platform::Objects::Base
      docs_category :issues
      model_name "IssueEvent"
      description "Represents a 'issue_comment_pinned' event on a given issue."

      scopeless_tokens_as_minimum

      implements Interfaces::TimelineEvent
      implements Interfaces::PerformableViaApp

      implements_node templates: [[:ricpe, :repo_id, :issue_id, :id]],
        as: "ICPE",
        ready_date: "1970-01-01" do |event|
        Timeline::Placeholder.async_value_for(event).then do |event|
          {
            prefix: :ricpe,
            repo_id: event.repository_id,
            issue_id: event.issue_id,
            id: event.id,
          }
        end
      end

      sig { params(permission: T.untyped, issue_event: ::IssueEvent).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_api_can_access?(permission, issue_event)
        permission.belongs_to_issue_event(issue_event)
      end

      sig { params(permission: T.untyped, issue_event: ::IssueEvent).returns(T.any(T::Boolean, Promise[T::Boolean])) }
      def self.async_viewer_can_see?(permission, issue_event)
        permission.belongs_to_issue(issue_event).then do |issue_event_accessible|
          next false unless issue_event_accessible

          issue_event.async_issue.then do |issue|
            if cap_filter = permission.cap_filter
              next false unless cap_filter.authorized_resources([issue]).any?
            end

            issue_event.async_subject.then do |subject|
              next false unless subject.is_a?(::IssueComment)
              subject.async_hide_from_user?(permission.viewer).then do |hidden|
                !hidden
              end
            end
          end
        end
      end

      field :issue_comment, IssueComment, "Identifies the issue comment associated with the 'issue_comment_pinned' event.", null: true

      def issue_comment
        @object.async_subject.then do |subject|
          next unless subject.is_a?(::IssueComment)
          subject
        end
      end
    end
  end
end
