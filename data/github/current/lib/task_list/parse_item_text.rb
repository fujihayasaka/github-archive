# typed: true
# frozen_string_literal: true

require "commonmarker"

class TaskList
  class ParseItemText < BaseOperation
    attr_reader :position, :replacement

    # Parses the item text of a task list item.
    #
    # position   - A two element Array of task list index and item index to select.
    #
    # Examples
    #
    #   TaskList::ParseItemText.new(position: [0, 0]).call(<<-MARKDOWN)
    #     - [ ] one
    #     - [ ] two
    #   MARKDOWN
    #   # => "one"
    def initialize(position:)
      @position = position
    end

    # Parse the text of a tasklist item.
    #
    # text - The Markdown String containing the task list to operate on.
    #
    # Returns the text of the item at the provided position or nil if the selection failed.
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
        (#{TaskList::Filter::ItemPrefixPattern}) # capture list prefix, i.e. - or 1.
        (#{TaskList::Filter::ItemPattern})       # capture checkbox
        (.*?)    # capture line item text
        (?:\R*)  # do not capture optional new line
        $
        /x

      # return the last match of the pattern, which is the line item text
      previous.match(pattern).captures&.last&.strip
    end
  end
end
