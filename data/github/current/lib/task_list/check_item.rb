# typed: true
# frozen_string_literal: true

require "commonmarker"

class TaskList
  # Models a checkbox selection operation of a task list item.
  class CheckItem < BaseOperation
    attr_reader :position, :checked

    # Create a task list item check operation to be performed on input text.
    #
    # position - A two element Array of task list index and item index to select.
    # checked  - The desired selection state of the checkbox.
    #
    # Examples
    #
    #   TaskList::CheckItem.new(source: [0, 0], checked: true).call(<<-MARKDOWN)
    #     - [ ] one
    #     - [ ] two
    #   MARKDOWN
    #   # => "- [x] one\n- [ ] two\n"
    def initialize(position:, checked:)
      @position = position
      @checked = checked
    end

    # Check or uncheck a task list item.
    #
    # text - The Markdown String containing the task list to operate on.
    #
    # Returns the mutated Markdown String or nil if the selection failed.
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

      # Change selection state.
      previous = text[range]
      replaced =
        if checked
          previous.sub(TaskList::Filter::IncompletePattern, "[x]")
        else
          previous.sub(TaskList::Filter::CompletePattern, "[ ]")
        end

      # No state change.
      return if previous == replaced

      text[range] = replaced
      text
    end
  end
end
