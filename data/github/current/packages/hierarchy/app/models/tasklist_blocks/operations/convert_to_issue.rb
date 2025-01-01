# typed: true
# frozen_string_literal: true

require "commonmarker"

module TasklistBlocks
  module Operations
    class ConvertToIssue
      include Parseable

      sig { params(position: T::Array[Integer], issue_builder: ::Issue::Builder).void }
      def initialize(position:, issue_builder:)
        @position = position
        @issue_builder = issue_builder
      end

      sig { params(text: String).returns(T.nilable(String)) }
      def call(text)
        return if text.nil?

        text = text.dup

        # Nothing to select.
        return if @position.nil?

        # Need list and item indexes.
        return if @position.length != 2

        # Client sent negative index.
        return if @position.any? { |index| index.nil? || index < 0 }

        tasklist_block_index, tasklist_item_index = @position

        # Normalize newlines. Ruby's default line separator is just \n.
        text.gsub!(/\r\n?/, "\n")

        # Parse source text into tree.
        root = CommonMarker.render_doc(text)

        # Find task list.
        tasklist_block = tasklist_blocks(root)[T.must(tasklist_block_index)]
        unless tasklist_block
          stat_failure_and_return(text, reason: "no_tasklist_block_found")
          return
        end

        # Find item to select.
        inner_text = tasklist_block.string_content
        tasklist_block_root = CommonMarker.render_doc(inner_text)
        tasklist_block_node = find_tasklist_block_node(tasklist_block_root)
        tasklist_items = tasklist_block_items(tasklist_block_node)
        tasklist_item = tasklist_items[T.must(tasklist_item_index)]
        unless tasklist_item
          stat_failure_and_return(text, reason: "no_tasklist_item_found")
          return
        end

        # Position text replacement indexes.
        range = range_for(tasklist_block, tasklist_item, text, inner_text)
        unless range
          stat_failure_and_return(text, reason: "no_range_found")
          return
        end

        text = convert_and_replace(text, range)
        text
      end

      private

      sig { params(text: String, range: T::Range[Integer]).returns(String) }
      def convert_and_replace(text, range)
        _, checkbox, title = T.must(text[range]).partition(TaskList::Filter::ItemPatternParser)
        title.squish!
        return stat_invalid_and_return(text) if already_an_issue?(title)
        new_issue = @issue_builder.build(issue: { title: title })
        new_issue.save
        return stat_failure_and_return(text) unless new_issue.persisted?

        text[range] = "#{checkbox.rstrip} #{new_issue.url}\n"
        text
      end

      sig { params(text: String, reason: String).returns(String) }
      def stat_failure_and_return(text, reason: "could_not_save")
        GitHub.dogstats.increment("tasklist_blocks.operation", tags: ["operation:ConvertToIssue", "status:failure", "reason:#{reason}"])
        text
      end

      sig { params(text: String).returns(String) }
      def stat_invalid_and_return(text)
        GitHub.dogstats.increment("tasklist_blocks.operation", tags: ["operation:ConvertToIssue", "status:invalid"])
        text
      end

      sig { params(title: String).returns(T::Boolean) }
      def already_an_issue?(title)
        ::GitHub::IssueReferenceParser.parse_reference(title).present?
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
