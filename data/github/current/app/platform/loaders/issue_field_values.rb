# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class IssueFieldValues < Platform::Loader
      # TODO issue_fields use specific interface instead of IIssueFieldValue
      sig { params(id: Integer).returns(Promise[T::Array[Issues::IIssueFieldValue]]) }
      def self.load(id)
        self.for.load(id)
      end

      # TODO issue_fields use specific interface instead of IIssueFieldValue
      sig { params(ids: T::Array[Integer]).returns(T::Hash[Integer, T::Array[Issues::IIssueFieldValue]]) }
      def fetch(ids)
        # TODO issue_fields
        {}
      end
    end
  end
end
