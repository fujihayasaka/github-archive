# typed: true
# frozen_string_literal: true

require "commonmarker"

class TaskList
  class ConvertToBlock
    attr_reader :position

    def initialize(position:)
      @position = position
    end

    def call(text)
      text = text.dup

      # Nothing to convert.
      return if position.nil?

      list_index = position

      # Normalize newlines. Ruby's default line spearator is just \n.
      text.gsub!(/\r\n?/, "\r\n")

      # Parse source text into tree.
      root = CommonMarker.render_doc(text)

      # Find task list.
      list = lists(root)[list_index]
      return unless list

      # Position text replacement indexes.
      range = range_for(list, text)
      return unless range

      # Replace text selection state.
      list_contents = text[range]

      # normalize the indentation of the list to a single level
      list_contents.gsub!(/\n#{TaskList::Filter::ItemPrefixPattern}/, "\n-")

      # strip out any whitespace so that we can always add it back in
      list_contents.strip!

      # wrap the list contents in the code fence
      spaced_wrapped_contents = "```[tasklist]\n#{list_contents}\n```"

      # make sure the list is either at the beginning, or has 2 newlines before it
      spaced_wrapped_contents.prepend("\n") if range.begin != 0 && text[range.begin - 2..range.begin - 1] != "\n\n"

      # make sure there is a newline after the list if it isn't at the end
      spaced_wrapped_contents += "\n" if range.end != text.length - 1 && text[range.end + 1] != "\n"

      text[range] = spaced_wrapped_contents
      text
    end

    private

    def lists(parent)
      parent.walk.select { |child| child.type == :list }
    end

    def range_for(node, text)
      TaskList::NodeRange.new.range_for_list_item(node, text)
    end
  end
end
