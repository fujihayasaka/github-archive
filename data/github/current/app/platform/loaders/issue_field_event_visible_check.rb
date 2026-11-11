# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueFieldEventVisibleCheck < Platform::Loader
      sig { params(viewer: T.nilable(User), event_id: Integer).returns(Promise[T::Boolean]) }
      def self.load(viewer, event_id)
        self.for(viewer).load(event_id)
      end

      sig { params(viewer: T.nilable(User)).void }
      def initialize(viewer)
        @viewer = viewer
      end

      sig { params(event_ids: T::Array[Integer]).returns(T::Hash[Integer, T::Boolean]) }
      def fetch(event_ids)
        details_by_event_id = IssueEventDetail
          .where(issue_event_id: event_ids)
          .pluck(:issue_event_id, :issue_field_id, :repository_id)
          .to_h { |event_id, field_id, repo_id| [event_id, { issue_field_id: field_id, repository_id: repo_id }] }

        issue_fields_by_id = IssueField
          .includes(:owner)
          .where(id: details_by_event_id.values.filter_map { |d| d[:issue_field_id] }.uniq)
          .index_by(&:id)

        event_ids.to_h do |event_id|
          detail = details_by_event_id[event_id]
          issue_field = detail && detail[:issue_field_id] && issue_fields_by_id[detail[:issue_field_id]]

          [event_id, issue_field ? issue_field.viewable_by?(viewer: @viewer, repository_id: detail[:repository_id]) : false]
        end
      end
    end
  end
end
