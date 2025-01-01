# typed: strict
# frozen_string_literal: true

# Public: Builds 1 or more prompts that fit within our token budget.
#
# Examples:
#
#   builder = Copilot::Prompt::Builder[SummarizeDiffHunksPrompt].new(items: diff_hunks, context: context, prompt_class: SummarizeDiffHunksPrompt)
#   builder.prompt_template = -> { SummarizeDiffHunksPrompt.new(pull_request: pull) }
#   builder.prompts
#   # => ["#<SummarizeDiffHunksPrompt items=[…]>", …]
#
#   # Attempt to split up an item if it's too big for a prompt
#   builder.item_too_big_strategy = -> (item) do
#     my_logic_to_split_up_item(item)
#   end
#   builder.prompts
#
module Copilot
  module Prompt
    class Builder
      extend T::Sig
      extend T::Generic
      include GitHub::Memoizer

      PromptType = type_member { { upper: Copilot::Prompt::Base[T.untyped] } } # rubocop:disable Sorbet/ForbidTUntyped
      PromptItem = type_member

      sig { returns(T::Array[PromptItem]) }
      attr_reader :items

      sig { returns(T.nilable(T.proc.returns(PromptType))) }
      attr_accessor :prompt_template

      sig { returns(T.proc.params(arg0: PromptItem).returns(T::Array[PromptItem])) }
      attr_accessor :item_too_big_strategy

      # Public: Initializes a new Builder
      #
      # items - An array of items to build the prompt(s) against
      sig { params(items: T::Array[PromptItem]).void }
      def initialize(items:)
        @items = items
        @item_too_big_strategy = T.let(-> (_) { [] }, T.proc.params(arg0: PromptItem).returns(T::Array[PromptItem]))
      end

      # Public: Builds 1 or more prompts of that fit in our allowed token budget.
      #
      # Returns an Array of Copilot::Prompt::Base instances.
      sig { returns(T::Array[PromptType]) }
      memoize def prompts
        GitHub.dogstats.time("copilot.prompt.builder_prompts", tags: ["size:#{items.size}", "prompt_class:#{prompt_template&.call&.class&.name}"]) do
          queue = items.dup

          [].tap do |coll|
            until queue.empty?
              prompt = build_prompt
              while queue.any? && prompt.add_item?(queue.first)
                prompt.add_item(queue.shift)
              end

              if prompt.items.none?
                # We couldn't add a single item to this prompt. The next item in the queue
                # is too big to fit in a prompt by itself. Run the `item_too_big_strategy`.
                # Defaults to dropping the troublesome item but could be configured to split
                # the big item up into smaller ones.
                replacements = Array.wrap(item_too_big_strategy.call(T.must(queue.shift)))
                queue.unshift(*replacements)
              else
                coll << prompt
              end
            end
          end
        end
      end

      sig { returns(PromptType) }
      def build_prompt
        raise "Expected prompt_template to be set on builder" unless prompt_template

        T.must(prompt_template).call
      end
    end
  end
end
