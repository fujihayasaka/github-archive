# typed: strict
# frozen_string_literal: true

module Copilot
  module Prompt
    class NaturalLanguageSearch < ::Copilot::Prompt::Base
      include GitHub::Memoizer

      PromptItem = type_member { { fixed: String } }

      sig do
        params(
          query: String,
        ).returns(
          T::Array[NaturalLanguageSearch]     # The return type is updated to NaturalLanguageSearch
        )
      end
      def self.prompts(query:)
        builder = ::Copilot::Prompt::Builder[NaturalLanguageSearch, PromptItem].new(items: [query])
        builder.prompt_template = -> { new(query:) }
        builder.prompts
      end

      sig { returns(String) }
      attr_reader :query

      sig { params(query: String).void }
      def initialize(query:)
        super()
        @query = query
      end

      sig { override.returns(T::Array[String]) }
      def stops
        []
      end

      sig { override.returns(::Copilot::Prompt::Type::TokenRange) }
      def baseline_expected_response_tokens
        60..120
      end

      sig { override.returns(::Copilot::Prompt::Type::TokenRange) }
      def per_item_expected_response_tokens
        90..180
      end

      sig { returns(Integer) }
      def max_tokens
        8_000
      end

      sig { override.params(item: PromptItem).returns(String) }
      def encode_item(item)
        ""
      end

      sig { override.params(item: PromptItem).returns(String) }
      def expand_item(item)
        ""
      end
    end
  end
end
