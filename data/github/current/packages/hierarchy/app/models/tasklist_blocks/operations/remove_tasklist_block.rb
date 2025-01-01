# typed: true
# frozen_string_literal: true

require "commonmarker"

module TasklistBlocks
  module Operations
    class RemoveTasklistBlock
      include Parseable

      attr_reader :position

      sig { params(position: Integer).void }
      def initialize(position:)
        @position = position
      end

      # Check or uncheck a task list item.
      #
      # text - The Markdown String containing the task list to operate on.
      #
      # Returns the mutated Markdown String or nil if the selection failed.
      sig { params(text: String).returns(T.nilable(String)) }
      def call(text)
        return if text.nil?

        text = text.dup

        # Client sent negative index.
        return if position.nil? || position < 0

        # Normalize newlines. Ruby's default line separator is just \n.
        text.gsub!(/\r\n?/, "\n")

        # Parse source text into tree.
        root = CommonMarker.render_doc(text)

        # Find task list.
        tasklist_block = tasklist_blocks(root)[position]
        return unless tasklist_block

        # Position text replacement indexes.
        range = range_for(tasklist_block, text)
        return unless range

        text[range] = ""
        text
      end

      private

      sig { params(node: CommonMarker::Node, text: String).returns(T.nilable(T::Range[Integer])) }
      def range_for(node, text)
        sourcepos = T.let(node.sourcepos, { start_line: Integer, start_column: Integer, end_line: Integer, end_column: Integer })
        lines = text.lines

        # Get all lines before start of [tasklist] block
        before = T.let(0...sourcepos[:start_line] - 1, T::Range[Integer])
        start = lines[before]&.sum(&:size)

        # Get all lines until end of codefence block for [tasklist]
        before = 0...sourcepos[:end_line]
        stop = lines[before]&.sum(&:size)

        start...stop
      end
    end
  end
end
