# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueFieldValues < Platform::Loader
      IssueFieldValueType = T.type_alias { T.any(Issues::IIssueFieldTextValue, Issues::IIssueFieldSingleSelectValue, Issues::IIssueFieldMultiSelectValue, Issues::IIssueFieldDateValue, Issues::IIssueFieldNumberValue) }

      sig { params(issue_id: Integer, repository_id: Integer, viewer: T.nilable(User)).returns(Promise[T::Array[IssueFieldValueType]]) }
      def self.load(issue_id, repository_id:, viewer: nil)
        self.for(viewer).load([repository_id, issue_id])
      end

      sig { params(viewer: T.nilable(User)).void }
      def initialize(viewer = nil)
        @viewer = T.let(viewer, T.nilable(User))
      end

      sig { params(keys: T::Array[[Integer, Integer]]).returns(T::Hash[[Integer, Integer], T::Array[IssueFieldValueType]]) }
      def fetch(keys)
        repository_ids = keys.map(&:first).uniq
        issue_ids = keys.map(&:last).uniq

        values_by_issue = Issues.domain.issue_fields.get_issue_field_values_from_issues(
          issue_ids,
          repository_ids: repository_ids
        )

        # Preload issue_field -> owner to avoid N+1 and AssociationRefused in viewable_by?
        all_values = values_by_issue.values.flatten
        ::ActiveRecord::Associations::Preloader.new(records: all_values, associations: { issue_field: :owner }).call if all_values.any?

        keys.index_with do |(repository_id, issue_id)|
          values = (values_by_issue[issue_id] || []).select { |v| v.repository_id == repository_id }
          Issues.domain.issue_fields.filter_visible_issue_field_values(values, viewer: @viewer)
        end
      end
    end
  end
end
