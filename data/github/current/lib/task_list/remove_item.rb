# typed: true
# frozen_string_literal: true

require "commonmarker"

class TaskList
  class RemoveItem < BaseOperation

    attr_reader :position

    # Create a task list item remove operation to be performed on input text.
    #
    # position   - A two element Array of task list index and item index to select.
    #
    # Examples
    #
    #   TaskList::RemoveItem.new(position: [0, 0]).call(<<-MARKDOWN)
    #     - [ ] one
    #     - [ ] two
    #   MARKDOWN
    #   # => "- [ ] two\n"
    sig { params(position: T::Array[Integer]).void }
    def initialize(position:)
      @position = position
    end

    # Remove a tasklist item.
    #
    # text - The Markdown String containing the task list to operate on.
    #
    # Returns the mutated Markdown String or nil if the selection failed.
    sig { params(text: String).returns(T.nilable(String)) }
    def call(text)
      return if text.nil?

      text = text.dup

      # Nothing to select.
      return text if position.nil?

      # Need list and item indexes.
      return text if position.length != 2

      # Client sent negative index.
      return text if position.any? { |index| index.nil? || index < 0 }

      list_index, item_index = position

      # Normalize newlines. Ruby's default line separator is just \n.
      text.gsub!(/\r\n?/, "\n")

      # Parse source text into tree.
      root = CommonMarker.render_doc(text)

      # Find task list.
      list = lists(root)[list_index]
      return text unless list

      item = items(list)[item_index]
      return text unless item

      range = range_for(item, text)
      return text unless range

      previous = text[range]
      pattern = /
              \A
              (#{TaskList::Filter::ItemPrefixPattern}) # capture list prefix, i.e. - or 1.
              (#{TaskList::Filter::ItemPattern})       # capture checkbox
              (.*?)     # capture line of text
              $         # continue until new line
              ((?:\r|\n)*) # capture any trailing newlines, if we dont this replaces the item with a blank new line
              /x

      # replace the fully matched line with an empty string, effectively removing the line
      replaced = previous&.sub(pattern) do |_|
        ""
      end

      text[range] = replaced
      text
    end
  end
end
