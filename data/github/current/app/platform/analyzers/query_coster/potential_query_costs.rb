# typed: true
# frozen_string_literal: true
module Platform
  module Analyzers
    class QueryCoster
      class PotentialQueryCosts < T::Struct
        const :corrected_rounding, T.nilable(Integer)

        sig { params(corrected_rounding: T.nilable(Integer)).void }
        def initialize(corrected_rounding:)
          super(corrected_rounding: corrected_rounding)
        end

        def to_hash
          serialize
        end
      end
    end
  end
end
