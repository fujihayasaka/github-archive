# typed: true
# frozen_string_literal: true

require "commonmarker"

module TasklistBlocks
  module Operations
    class UpdateTasklistTitle
      extend T::Sig
      include Parseable

      # Pattern used for matching tasklist title
      TASKLIST_TITLE_SELECTOR = /(^#*) #{TaskList::Filter::IssueTextPattern}/

      sig { params(position: Integer, name: String).void }
      def initialize(position:, name:)
        @position = position
        @name = name
      end

      # Update a tasklist's title.
      #
      # text - The Markdown String containing the task list to operate on.
      #
      # Returns the mutated Markdown String or nil if the selection failed.
      sig { params(text: String).returns(T.nilable(String)) }
      def call(text)
        return if text.nil?

        text = text.dup

        # Client sent negative index.
        return if @position < 0

        if @name.length.to_i > 255
          stat_warning("name_too_long")
        end

        # Normalize newlines. Ruby's default line separator is just \n.
        text.gsub!(/\r\n?/, "\n")

        # Parse source text into tree.
        root = CommonMarker.render_doc(text)
        # Find task list.
        tasklist_block = tasklist_blocks(root)[@position]
        return unless tasklist_block

        # Find item to select.
        inner_text = tasklist_block.string_content

        # Position text replacement indexes.
        range = range_for(tasklist_block, text, inner_text)
        unless range
          stat_failure("no_range_found")
          return
        end

        # Title is an optional field
        if @name.empty?
          text[range] = ""
        else
          text[range] = "### #{@name}\n"
        end

        text
      end

      private

      sig { params(reason: String).void }
      def stat_failure(reason)
        GitHub.dogstats.increment("tasklist_blocks.operation", tags: ["operation:UpdateTasklistTitle", "status:failure", "reason:#{reason}"])
      end

      sig { params(reason: String).void }
      def stat_warning(reason)
        GitHub.dogstats.increment("tasklist_blocks.operation", tags: ["operation:UpdateTasklistTitle", "status:warning", "reason:#{reason}"])
      end

      # Private: Find the range of text to replace.
      # Given the block node, the body, and the inner text
      # find the range of string characters to replace.
      #
      # Example return: 14..25
      # Returns a Range.
      sig do
        params(
          tasklist_block_node: CommonMarker::Node,
          body: String,
          tasklist_block_text: String
        ).returns(T.nilable(T::Range[Integer]))
      end
      def range_for(tasklist_block_node, body, tasklist_block_text)
        block_sourcepos = T.let(tasklist_block_node.sourcepos, { start_line: Integer, start_column: Integer, end_line: Integer, end_column: Integer })
        block_lines = body.lines
        item_lines = tasklist_block_text.lines

        block_before = 0...block_sourcepos[:start_line]
        start = block_lines[block_before]&.sum(&:size)

        end_index = if item_lines[0]&.match(TASKLIST_TITLE_SELECTOR)
          item_lines[0]&.size
        else
          0
        end
        return unless start && end_index

        stop = start + end_index
        start...stop
      end
    end
  end
end
