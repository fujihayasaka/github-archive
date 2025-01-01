# typed: strict
# frozen_string_literal: true

module Copilot
  module Prompt
    module Tokens
      include GitHub::Memoizer

      CHARACTERS_PER_TOKEN = 4.0

      sig { returns(Integer) }
      def max_tokens
        4_096
      end

      sig { returns(T::Array[String]) }
      def stops
        []
      end

      sig { params(plain_text: T.nilable(String)).returns(Integer) }
      def count_tokens(plain_text)
        return 0 if plain_text.nil?
        (plain_text.size / CHARACTERS_PER_TOKEN).ceil
      end
    end
  end
end
