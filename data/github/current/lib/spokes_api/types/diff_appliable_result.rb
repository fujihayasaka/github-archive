# typed: strict
# frozen_string_literal: true

module SpokesAPI
  module Types
    class DiffAppliableResult < T::Enum
      enums do
        Appliable = new(:DIFF_APPLIABLE_RESULT_APPLIABLE)
        Conflicts = new(:DIFF_APPLIABLE_RESULT_CONFLICTS)
        InvalidCommit = new(:DIFF_APPLIABLE_RESULT_INVALID_COMMIT)
        MalformedPatch = new(:DIFF_APPLIABLE_RESULT_MALFORMED_PATCH)
        AlreadyApplied = new(:DIFF_APPLIABLE_RESULT_ALREADY_APPLIED)
        Unknown = new(:unknown)
      end

      sig { params(value: T.untyped).returns(DiffAppliableResult) }
      def self.safe_deserialize(value)
        deserialize(value)
      rescue KeyError
        Unknown
      end
    end
  end
end
