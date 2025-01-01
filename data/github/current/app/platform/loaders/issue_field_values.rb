# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueFieldValues < Platform::Loader
      IssueFieldValueType = T.type_alias { T.any(Issues::IIssueFieldTextValue, Issues::IIssueFieldSingleSelectValue, Issues::IIssueFieldDateValue, Issues::IIssueFieldNumberValue) }

      sig { params(id: Integer).returns(Promise[T::Array[IssueFieldValueType]]) }
      def self.load(id)
        self.for.load(id)
      end

      sig { params(ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[IssueFieldValueType]]) }
      def fetch(ids)
        Issues.domain.issue_fields.get_issue_field_values_from_issues(ids)
      end
    end
  end
end
