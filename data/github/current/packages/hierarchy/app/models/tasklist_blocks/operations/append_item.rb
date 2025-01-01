# typed: true
# frozen_string_literal: true

require "commonmarker"

module TasklistBlocks
  module Operations
    class AppendItem
      extend T::Sig
      include Parseable

      attr_reader :position, :value

      sig { params(position: Integer, value: String).void }
      def initialize(position:, value:)
        @position = position
        @value = value
      end

      # Check or uncheck a task list item.
      #
      # text - The Markdown String containing the task list to operate on.
      #
      # Returns the mutated Markdown String or nil if the selection failed.
      sig { params(text: T.nilable(String)).returns(T.nilable(String)) }
      def call(text)
        return if text.nil?

        text = text.dup

        # Client did not send position index
        return if position.nil?

        # Normalize newlines. Ruby's default line separator is just \n.
        text.gsub!(/\r\n?/, "\n")

        # Parse source text into tree.
        root = CommonMarker.render_doc(text)

        # Find task list.
        tasklist_block = tasklist_blocks(root)[position]
        unless tasklist_block
          stat_failure("no_tasklist_block_found")
          return
        end

        # Position text replacement indexes.
        range = range_for(tasklist_block, text)
        unless range
          stat_failure("no_range_found")
          return
        end

        inner_text = tasklist_block.string_content
        item_prefix_match = TaskList::Filter::ItemPrefixPattern.match(inner_text)
        item_prefix = item_prefix_match ? item_prefix_match[0].try(:strip) : "-"

        original_text = text[range]
        text[range] = "#{item_prefix} [ ] #{value}\n#{original_text}"
        text
      end

      private

      sig { params(reason: String).void }
      def stat_failure(reason)
        GitHub.dogstats.increment("tasklist_blocks.operation", tags: ["operation:AppendItem", "status:failure", "reason:#{reason}"])
      end

      sig { params(node: CommonMarker::Node, text: String).returns(T.nilable(T::Range[Integer])) }
      def range_for(node, text)
        sourcepos = T.let(node.sourcepos, { start_line: Integer, start_column: Integer, end_line: Integer, end_column: Integer })
        lines = text.lines

        before = T.let(0...sourcepos[:end_line] - 1, T::Range[Integer])

        start = lines[before]&.sum(&:size)
        stop = lines[before]&.sum(&:size)

        start...stop
      end
    end
  end
end
