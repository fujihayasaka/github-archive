# typed: true
# frozen_string_literal: true

require "commonmarker"

module TasklistBlocks
  module Operations
    class UpdateItemPosition
      include Parseable

      sig { params(src: T::Array[Integer], dst: T::Array[Integer]).void }
      def initialize(src:, dst:)
        @src = src
        @dst = dst
      end

      # Public: returns the updated text with the item at the given src position
      # moved to the dst position.
      #
      # Returns a string
      sig { params(text: String).returns(T.nilable(String)) }
      def call(text)
        return if src_or_dst_invalid?
        return if text.nil?

        text = text.dup

        # Normalize newlines. Ruby's default line separator is just \n.
        text.gsub!(/\r\n?/, "\n")

        source_range = build_range(text, @src)
        destination_range = build_range(text, @dst)
        unless source_range && destination_range
          unless source_range || destination_range
            stat_failure("no_source_or_destination_range")
            return
          end
          stat_failure(source_range ? "no_destination_range" : "no_source_range")
          return
        end

        source_text = text[source_range]
        destination_text = text[destination_range]

        # If source is greater than destination, we need to move the item up
        # If source is less than destination, we need to move the item down
        if source_range.begin > destination_range.begin
          text[source_range] = ""
          text[destination_range] = "#{source_text}#{destination_text}"
        else
          text[destination_range] = @src[0] == @dst[0] ? "#{destination_text}#{source_text}" : "#{source_text}#{destination_text}"
          text[source_range] = ""
        end

        text
      end

      private

      sig { params(reason: String).void }
      def stat_failure(reason)
        GitHub.dogstats.increment("tasklist_blocks.operation", tags: ["operation:UpdateItemPosition", "status:failure", "reason:#{reason}"])
      end

      sig { params(text: String, positions: T::Array[Integer]).returns(T.nilable(T::Range[Integer])) }
      def build_range(text, positions)
        tasklist_block_index, tasklist_item_index = positions

        # Parse source text into tree.
        root = CommonMarker.render_doc(text)

        # Find task list.
        tasklist_block = tasklist_blocks(root)[T.must(tasklist_block_index)]
        return unless tasklist_block

        # Find item to select.
        inner_text = tasklist_block.string_content

        tasklist_block_root = CommonMarker.render_doc(inner_text)
        tasklist_block_node = find_tasklist_block_node(tasklist_block_root)
        tasklist_items = tasklist_block_items(tasklist_block_node)
        tasklist_item = tasklist_items[T.must(tasklist_item_index)]

        # Position text replacement indexes.
        range_for(tasklist_block, tasklist_item, text, inner_text)
      end

      sig { returns(T::Boolean) }
      def src_or_dst_invalid?
        return true if @src.empty? || @dst.empty?
        return true unless @src.length == 2 && @dst.length == 2
        return true if @src == @dst
        return true if (@src + @dst).any?(&:negative?)

        false
      end

      # Private: Find the range of text to replace.
      # Given the block, the item node, the body and the inner text, find the
      # range of string characters to replace.
      #
      # Example return: 14..25
      # Returns a Range.
      sig { params(tasklist_block_node: CommonMarker::Node, tasklist_item_node: T.nilable(CommonMarker::Node), body: String, tasklist_block_text: String).returns(T::Range[Integer]) }
      def range_for(tasklist_block_node, tasklist_item_node, body, tasklist_block_text)
        block_sourcepos = tasklist_block_node.sourcepos
        item_sourcepos = tasklist_item_node&.sourcepos
        block_lines = body.lines
        item_lines = tasklist_block_text.lines

        block_before = 0...block_sourcepos[:start_line]
        start = T.must(block_lines[block_before]).sum(&:size)

        item_before = item_sourcepos ? 0...item_sourcepos[:end_line] - 1 : 0...tasklist_block_text.lines.length
        start += T.must(tasklist_block_text.lines[item_before]).sum(&:size)

        stop = start + (item_sourcepos ? T.must(item_lines[item_sourcepos[:end_line] - 1]).size : 0)

        start...stop
      end
    end
  end
end
