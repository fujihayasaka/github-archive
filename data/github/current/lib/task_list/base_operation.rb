# typed: true
# frozen_string_literal: true

require "commonmarker"

class TaskList
  class BaseOperation
    # Filters the child nodes down to lists (task and normal). Move operations
    # identify the lists with a 0-based index that indexes into the returned
    # Array.
    #
    # parent - The CommonMarker::Node to search.
    #
    # Returns an Array of list nodes.
    private def lists(parent)
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
    private def items(parent)
      parent.select { |child| child.type == :list_item }
    end

    private def range_for(node, text)
      TaskList::NodeRange.new.range_for_list_item(node, text)
    end
  end
end
