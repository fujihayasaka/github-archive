# typed: true
# frozen_string_literal: true

require "commonmarker"

class TaskList
  # Models a checkbox selection operation of a task list item.
  class RenameItem
    attr_reader :position, :replacement

    # Create a task list item rename operation to be performed on input text.
    #
    # position   - A two element Array of task list index and item index to select.
    # replacement - The desired string replacement for the item.
    #
    # Examples
    #
    #   TaskList::RenameItem.new(source: [0, 0], replacement: "new one").call(<<-MARKDOWN)
    #     - [ ] one
    #     - [ ] two
    #   MARKDOWN
    #   # => "- [x] new one\n- [ ] two\n"
    def initialize(position:, replacement:)
      @position = position
      @replacement = replacement
    end

    # Replace task list item's text.
    #
    # text - The Markdown String containing the task list to operate on.
    #
    # Returns the mutated Markdown String or nil if text replacement failed.
    def call(text)
      text = text.dup

      # Nothing to select.
      return if position.nil?

      # Need list and item indexes.
      return if position.length != 2

      # Client sent negative index.
      return if position.any? { |index| index.nil? || index < 0 }

      list_index, item_index = position

      # Normalize newlines. Ruby's default line spearator is just \n.
      text.gsub!(/\r\n?/, "\r\n")

      # Parse source text into tree.
      root = CommonMarker.render_doc(text)

      # Find task list.
      list = lists(root)[list_index]
      return unless list

      # Find item to select.
      item = items(list)[item_index]
      return unless item

      # Position text replacement indexes.
      range = range_for(item, text)
      return unless range

      # Replace text selection state.
      previous = text[range]

      pattern = /
              \A
              (#{TaskList::Filter::ItemPrefixPattern})
              (#{TaskList::Filter::ItemPattern})
              (.*?)    # capture current text
              (\R*)    # capture optional new line
              $
              /x

      replaced = previous.sub(pattern) do |_|
        match = T.must(Regexp.last_match)
        item_prefix = match[1]
        item_state = match[2]
        new_line_break = match[5]
        "#{item_prefix}#{item_state} #{replacement}#{new_line_break}"
      end

      # No change.
      return if previous == replaced

      text[range] = replaced
      text
    end

    private

    # Filters the child nodes down to lists (task and normal). Move operations
    # identify the lists with a 0-based index that indexes into the returned
    # Array.
    #
    # parent - The CommonMarker::Node to search.
    #
    # Returns an Array of list nodes.
    def lists(parent)
      parent.walk.select { |child| child.type == :list }
    end

    # Filters a list's child nodes down to list items.
    #
    # We do this in case a non-list-item node is a child of the list parent.
    # I'm not sure if that's allowed by the spec, though.
    #
    # parent - The CommonMarker::Node list to search.
    #
    # Returns an Array of list item nodes.
    def items(parent)
      parent.select { |child| child.type == :list_item }
    end

    def range_for(node, text)
      TaskList::NodeRange.new.range_for_list_item(node, text)
    end
  end
end
