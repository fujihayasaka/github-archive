# typed: strict
# frozen_string_literal: true

# Public: Shared base class for Copilot prompts. Handles logic for whether or not the prompt can include more items based on the rendered token count and how many tokens we expect to get back from the model.
#
# Increments range of expected response tokens every time a new item is added to the prompt.
#
# Examples
#
#   class MyPrompt < Copilot::Prompt::Base
#     def baseline_expected_response_tokens
#       25..50
#     end
#
#     def per_item_expected_response_tokens
#       10..20
#     end
#   end
#   prompt = MyPrompt.new(context: context)
#
#   items = issue.comments
#   items.each do |item|
#     prompt.add_item(item) if prompt.add_item?(item)
#   end
#
#   prompt.render
#   # => "Prompt string…"
#
module Copilot
  module Prompt
    class Base
      extend T::Helpers
      extend T::Generic
      include GitHub::Memoizer
      include Tokens

      PromptItem = type_member

      abstract!

      sig { abstract.returns(Type::TokenRange) }
      def baseline_expected_response_tokens
      end

      sig { abstract.returns(Type::TokenRange) }
      def per_item_expected_response_tokens
      end

      sig { abstract.params(item: PromptItem).returns(String) }
      def encode_item(item)
      end

      sig { abstract.params(item: PromptItem).returns(String) }
      def expand_item(item)
      end

      sig { returns(T::Array[PromptItem]) }
      attr_accessor :items

      sig { returns(T::Array[Message]) }
      attr_accessor :messages

      sig { returns(Type::TokenRange) }
      attr_accessor :expected_response_tokens

      sig { void }
      def initialize
        @items = T.let([], T::Array[PromptItem])
        @messages = T.let([], T::Array[Message])
        @expected_response_tokens = T.let(baseline_expected_response_tokens.dup, Type::TokenRange)
      end

      # Public: Do we have enough token budget to add another item to this prompt?
      #
      # Returns a Boolean.
      sig { params(item: PromptItem).returns(T::Boolean) }
      def add_item?(item)
        rendered = with(items: items + [item]) do
          render
        end
        request_tokens = count_tokens(rendered)
        min_response_tokens = expected_response_tokens.min + per_item_expected_response_tokens.min

        request_tokens + min_response_tokens <= max_tokens
      end

      # Public: Adds the given item to this prompt and increments our expected
      # response tokens accordingly.
      #
      # item - An Object
      #
      # Returns nothing.
      sig { params(item: PromptItem).void }
      def add_item(item)
        incr_expected_response_tokens(by: per_item_expected_response_tokens)

        items << item
      end

      # Public: Renders the prompt template. Clears references and messages each time so
      # that they will only include the ones that are used in the current rendered prompt.
      #
      # Returns a String.
      sig { returns(String) }
      def render
        references.clear
        @messages = []

        ActionView::Base.with(annotate_rendered_view_with_filenames: false) do
          view_context.render(template, content_type: "text/plain").to_str
        end
      end

      # Public: Collects references made in the rendered prompts and handles
      # coordination for encoding, decoding, and expanding references. Both in the
      # prompt itself and the resulting completion.
      sig { returns(Copilot::Prompt::ReferenceEncoder[PromptItem]) }
      memoize def references
        Copilot::Prompt::ReferenceEncoder[PromptItem].new(prompt: self)
      end

      # Public: Does the response seem valid for this response. Currently
      # only checks if response size falls withing our expected token count.
      #
      # response - A String response from the model.
      #
      # Returns a Boolean.
      sig { params(response: String).returns(T::Boolean) }
      def valid_response?(response)
        expected_response_tokens.cover?(count_tokens(response))
      end

      private

      # Private: Builds an action view we can use to render the template.
      #
      # Returns an ActionView::Base object.
      sig { returns(ActionView::Base) }
      memoize def view_context
        EmptyController.new.view_context
      end

      # Private: Builds the corresponding template for this prompt.
      #
      # Returns an instance of Copilot::Prompt::Template.
      sig { returns(Copilot::Prompt::Template[PromptItem]) }
      memoize def template
        klass = "#{self.class.name}Template".constantize
        klass.new(self)
      end

      # Private: Increases our expected response token range using another range.
      #
      # by - The Range to increase by
      #
      # Returns nothing.
      sig { params(by: Type::TokenRange).void }
      def incr_expected_response_tokens(by:)
        min = expected_response_tokens.min + by.min
        max = expected_response_tokens.max + by.max
        self.expected_response_tokens = min..max
      end
    end
  end
end
