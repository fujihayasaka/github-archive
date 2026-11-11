# typed: strict
# frozen_string_literal: true

module TasklistBlocks
  module Operations
    # Common methods to mix into our operations
    module Parseable
      sig { params(parent: CommonMarker::Node).returns(T::Array[CommonMarker::Node]) }
      def tasklist_blocks(parent)
        parent.walk.select do |child|
          child.type == :code_block && child.fence_info == "[tasklist]"
        end
      end

      sig { params(root: CommonMarker::Node).returns(CommonMarker::Node) }
      def find_tasklist_block_node(root)
        root.walk.find do |child|
          child.type == :list
        end
      end

      sig { params(tasklist_block: T.nilable(CommonMarker::Node)).returns(T::Array[CommonMarker::Node]) }
      def tasklist_block_items(tasklist_block)
        return [] unless tasklist_block

        tasklist_block.select do |child|
          # only parse list items that have some content i.e ignore empty list items
          # hierarchy of nodes for a valid child should look like:
          # 1. list_item -> paragraph -> text, where the text node contains the item's content
          # 2. list item -> paragraph -> [child nodes], where the child nodes contain a combination of markdown styling and text

          match = TaskList::Filter::TrackedIssuePatternParser.match(child&.first_child&.first_child&.string_content)
          item_contains_text = match && match[2].present?
          child&.type == :list_item && (item_contains_text || item_contains_markdown_styling?(child))
        end
      end

      # Checks for a tasklist item that has markdown styling
      # Ex. - [ ] **bold** issue
      sig { params(item: T.nilable(CommonMarker::Node)).returns(T::Boolean) }
      def item_contains_markdown_styling?(item)
        return false if item.nil?
        return false unless item.first_child&.type == :paragraph
        item.first_child&.to_a&.size > 1
      end
    end
  end
end
