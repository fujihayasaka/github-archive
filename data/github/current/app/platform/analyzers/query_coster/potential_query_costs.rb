# typed: strict
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryCoster
      class PotentialQueryCosts < T::Struct
        const :corrected_parent_request_count, T.nilable(Integer)

        sig do
          params(
            corrected_parent_request_count: T.nilable(Integer)
          ).void
        end
        def initialize(corrected_parent_request_count:
        )
          super(
            corrected_parent_request_count: corrected_parent_request_count
          )
        end

        # value can be either a number, boolean or nil
        sig { returns(T::Hash[Symbol, T.nilable(T.any(Integer, T::Boolean))]) }
        def to_hash
          serialize
        end
      end
    end
  end
end
