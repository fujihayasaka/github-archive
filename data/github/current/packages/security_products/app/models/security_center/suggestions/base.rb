# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module Suggestions
    class Base
      extend T::Helpers
      include GitHub::Memoizer

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
      def initialize(selected_values: [], value: "", limit: max_allowed_limit)
        @selected_values = selected_values
        @value = value

        new_limit = max_allowed_limit
        new_limit = [limit, max_allowed_limit].min if limit.present?
        @limit = T.let(new_limit, Integer)
      end

      sig { overridable.returns(Integer) }
      def max_allowed_limit
        20
      end

      sig { abstract.returns(T::Array[Suggestion]) }
      def suggestions; end
    end
  end
end
