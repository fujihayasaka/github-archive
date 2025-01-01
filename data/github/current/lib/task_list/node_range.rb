# typed: true
# frozen_string_literal: true

class TaskList
  class NodeRange
    # Converts the source position from a tree node annotation into an absolute
    # range within the original text.
    #
    # node - The CommonMarker::Node to locate in the source.
    # text - The Markdown String that was parsed.
    #
    # Returns the node's Range within the String.
    def range_for_list_item(node, text)
      sourcepos = node.sourcepos
      lines = text.lines

      before = 0...sourcepos[:start_line] - 1
      start = lines[before].sum(&:size)

      before = 0...sourcepos[:end_line] - 1
      stop = lines[before].sum(&:size)

      stop +=
        if loose?(node)
          # Loose list items already include all line terminators.
          sourcepos[:end_column] - 1
        else
          # Include line terminator at end of tight list items.
          lines[sourcepos[:end_line] - 1].size - 1
        end

      start..stop
    end

    private

    # A loose list item node contains paragraph child nodes.
    #
    #   http://spec.commonmark.org/0.25/#loose
    #
    # We can identify a loose item by its ending at column 0 of the following
    # line, before the line terminator characters begin.
    #
    # The parser does not include the line terminator characters in tight
    # items, so we add them onto the end of the text when splicing it out.
    #
    # The parser has already included the line terminators in loose items, so
    # we don't need to add any extra.
    #
    # node - The CommonMarker::Node for the list item.
    #
    # Returns true if it's loose, false if it's tight.
    def loose?(node)
      node.sourcepos[:end_column] == 0
    end
  end
end
