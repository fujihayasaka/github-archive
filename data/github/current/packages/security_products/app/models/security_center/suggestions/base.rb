# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    class Base
      extend T::Helpers
      include GitHub::Memoizer

      MAX_ALLOWED_SUGGESTIONS = 20

      abstract!

      sig { returns(T::Array[String]) }; attr_reader :selected_values
      sig { returns(String) }; attr_reader :value
      sig { returns(Integer) }; attr_reader :limit

      sig do
        params(
          selected_values: T::Array[String],
          value: String,
          limit: T.nilable(Integer)
        ).void
      end
      def initialize(selected_values: [], value: "", limit: MAX_ALLOWED_SUGGESTIONS)
        @selected_values = selected_values
        @value = value

        limit ||= MAX_ALLOWED_SUGGESTIONS
        @limit = T.let([limit, MAX_ALLOWED_SUGGESTIONS].min, Integer)
      end

      sig { abstract.returns(T::Array[Suggestion]) }
      def suggestions; end
    end
  end
end
