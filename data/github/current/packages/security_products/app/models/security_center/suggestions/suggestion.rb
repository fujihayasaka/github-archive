# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    class Suggestion < T::Struct

      const :description, T.nilable(String)
      const :label, T.nilable(String)
      const :value, String

      sig { params(other: Suggestion).returns(T::Boolean) }
      def ==(other)
        description == other.description &&
          label == other.label &&
          value == other.value
      end
    end
  end
end
