# typed: true
# frozen_string_literal: true

require "commonmarker"

class TaskList
  # Models a move operation of a task list item from its source list to a
  # destination list. The destinaton may be a new location in its original
  # list or a separate list within the same Markdown text.
  #
  # CommonMarker annotates each AST node with the source position in the
  # original text that generated it.
  #
  # This allows us to parse the source into an AST, find the list item offset,
  # and splice it into its new location. A round-trip from source text to tree
  # and back into text is not required.
  class MoveItem < BaseOperation
    attr_reader :source, :dest

    # Create a task list item move operation to be performed on input text.
    #
    # source - A two element Array of task list index and item index to move.
    # dest   - A two element Array of the task list index and item index after
    #          which the source item is appended.
    #
    # Examples
    #
    #   TaskList::MoveItem.new(source: [0, 0], dest: [0, 1]).call(<<-MARKDOWN)
    #     - [ ] one
    #     - [ ] two
    #   MARKDOWN
    #   # => "- [ ] two\n- [ ] one\n"
    def initialize(source:, dest:)
      @source = source
      @dest = dest
    end

    # Moves a list item from its original location to a new destination.
    #
    # text - The Markdown String containing the task list.
    #
    # Returns the mutated Markdown String or nil if the move failed.
    def call(text)
      text = text.dup

      # Nothing to move.
      return if source.nil? || dest.nil? || source == dest

      # Need list and item indexes.
      return if source.length != 2 || dest.length != 2

      # Client sent negative index.
      return if source.any? { |index| index.nil? || index < 0 }
      return if dest.any? { |index| index.nil? || index < 0 }

      source_list_index, source_item_index = source
      dest_list_index, dest_item_index = dest

      # Normalize newlines. Ruby's default line spearator is just \n.
      text.gsub!(/\r\n?/, "\r\n")

      # Parse source text into tree.
      root = CommonMarker.render_doc(text)

      # Find top-level task lists.
      source_list, dest_list = lists(root).values_at(source_list_index, dest_list_index)
      return unless source_list && dest_list

      # Find item to move and its new sibling.
      source_item = items(source_list)[source_item_index]
      dest_items = items(dest_list)
      move = if dest_item_index >= dest_items.size
        { operation: :append, anchor: dest_items.last }
      else
        { operation: :prepend, anchor: dest_items[dest_item_index] }
      end
      return unless source_item && move[:anchor]

      # Position text replacement indexes.
      source_range = range_for(source_item, text)
      dest_range = range_for(move[:anchor], text)
      return unless source_range && dest_range

      # Align moved list with its new parent's indentation.
      indent_width = dest_list.sourcepos[:start_column] - 1

      if source_range.first < dest_range.first
        # Move list item text down.
        item = text.slice(source_range)

        if move[:operation] == :append
          append(text, dest_range, item, indent_width)
        else
          prepend(text, dest_range, item, indent_width)
        end

        text.slice!(source_range)
      else
        # Move list item text up.
        item = text.slice!(source_range)

        if move[:operation] == :append
          append(text, dest_range, item, indent_width)
        else
          prepend(text, dest_range, item, indent_width)
        end
      end

      text
    end

    private

    def append(text, dest, item, width)
      indent = TaskList::Indent.new
      item = indent.match(item, width)
      item = "\n" + item if text[dest.last] != "\n"
      text.insert(dest.last + 1, item)
    end

    def prepend(text, dest, item, width)
      indent = TaskList::Indent.new
      item = indent.match(item, width)
      item += "\n" if !item.end_with?("\n")
      text.insert(dest.first, item)
    end
  end
end
