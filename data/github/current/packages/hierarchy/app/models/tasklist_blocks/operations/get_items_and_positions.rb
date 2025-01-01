# typed: true
# frozen_string_literal: true

require "commonmarker"

module TasklistBlocks
  module Operations
    class GetItemsAndPositions
      include Parseable

      def initialize
      end

      # Get all of the items and their positions in a given body
      #
      # text - The Markdown String containing the task list to operate on.
      #
      # Returns the mutated Markdown String or nil if the selection failed.
      sig { params(text: String).returns(T::Array[T::Array[ItemWithPosition]]) }
      def call(text)
        text = text.dup

        # Normalize newlines. Ruby's default line separator is just \n.
        text.gsub!(/\r\n?/, "\n")

        # Parse source text into tree.
        root = CommonMarker.render_doc(text)

        # Find task list
        blocks = tasklist_blocks(root)
        return [] unless blocks.length > 0

        # for each task list...
        blocks.each_with_index.map do |block, block_index|
          # get the items for that tasklist
          inner_text = block.string_content
          tasklist_block_root = CommonMarker.render_doc(inner_text)
          tasklist_block_node = find_tasklist_block_node(tasklist_block_root)
          tasklist_items = tasklist_block_items(tasklist_block_node)

          # and for each item in the tasklist...
          tasklist_items.each_with_index.filter_map do |tasklist_item, item_index|
            # parse it, try and parse an issue reference off the text, and note it's position
            range = range_for(block, tasklist_item, text, inner_text)
            next unless range

            _, checkbox, title = T.must(text[range]).partition(TaskList::Filter::ItemPatternParser)
            title.squish!
            ItemWithPosition.new(
              text: title,
              position: [block_index, item_index]
            )
          end
        end
      end

      # Private: Find the range of text to replace.
      # Given the block, the item node, the body and the inner text, find the
      # range of string characters to replace.
      #
      # Example return: 14..25
      # Returns a Range.
      sig do
        params(
          tasklist_block_node: CommonMarker::Node,
          tasklist_item_node: CommonMarker::Node,
          body: String,
          tasklist_block_text: String
        ).returns(T.nilable(T::Range[Integer]))
      end
      def range_for(tasklist_block_node, tasklist_item_node, body, tasklist_block_text)
        block_sourcepos = T.let(tasklist_block_node.sourcepos, { start_line: Integer, start_column: Integer, end_line: Integer, end_column: Integer })
        item_sourcepos = T.let(tasklist_item_node.sourcepos, { start_line: Integer, start_column: Integer, end_line: Integer, end_column: Integer })
        block_lines = body.lines
        item_lines = tasklist_block_text.lines

        block_before = 0...block_sourcepos[:start_line]
        start = block_lines[block_before]&.sum(&:size)

        item_before = 0...item_sourcepos[:end_line] - 1
        start_index = tasklist_block_text.lines[item_before]&.sum(&:size)
        end_index = item_lines[item_sourcepos[:end_line] - 1]&.size
        return unless start && start_index && end_index

        start += start_index
        stop = start + end_index

        start...stop
      end
    end
  end
end
