# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueFieldValues < Platform::Loader
      IssueFieldValueType = T.type_alias { T.any(Issues::IIssueFieldTextValue, Issues::IIssueFieldSingleSelectValue, Issues::IIssueFieldDateValue, Issues::IIssueFieldNumberValue) }

      sig { params(id: Integer, viewer: T.nilable(User)).returns(Promise[T::Array[IssueFieldValueType]]) }
      def self.load(id, viewer: nil)
        self.for(viewer).load(id)
      end

      sig { params(viewer: T.nilable(User)).void }
      def initialize(viewer = nil)
        @viewer = viewer
      end

      sig { params(ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[IssueFieldValueType]]) }
      def fetch(ids)
        values_by_issue = Issues.domain.issue_fields.get_issue_field_values_from_issues(ids)

        # Preload issue_field -> owner to avoid N+1 and AssociationRefused in viewable_by?
        all_values = values_by_issue.values.flatten
        ::ActiveRecord::Associations::Preloader.new(records: all_values, associations: { issue_field: :owner }).call if all_values.any?

        # Filter each issue's values by viewer visibility using the domain method
        values_by_issue.transform_values do |values|
          Issues.domain.issue_fields.filter_visible_issue_field_values(values, viewer: @viewer)
        end
      end
    end
  end
end
