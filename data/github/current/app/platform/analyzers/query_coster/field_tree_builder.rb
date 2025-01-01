# typed: strict
# frozen_string_literal: true

module Platform
  module Analyzers
    class QueryCoster
      # FieldTreeBuilder incrementally builds a mutable tree of Field objects as a GraphQL query is analyzed.
      # Because Field objects are constructed as the query is traversed, their parent/child relationships may be incomplete
      # until the entire query has been processed. Once building is complete, FieldTreeBuilder produces an immutable FieldTree
      # (composed of FieldTreeNode objects) that is fully connected and safe for traversal, debugging, and cost analysis.
      class FieldTreeBuilder

        sig { returns(T::Array[Field]) }
        attr_reader :root_fields

        sig { void }
        def initialize
          @root_fields = T.let([], T::Array[Field])
          @active_path = T.let([], T::Array[Field])
        end

        # Called when entering a new field. Adds the field as a child of the currently active field,
        # or as a root if there's no active field.
        sig { params(field: Field).void }
        def enter_field(field)
          if @active_path.empty?
            @root_fields << field
          else
            # Check if the field is actually a field, or if it's an inline fragment.
            if field.ast_node.is_a?(GraphQL::Language::Nodes::Field)
              T.must(@active_path.last).add_child(field)
            elsif field.ast_node.is_a?(GraphQL::Language::Nodes::InlineFragment)
              # If it's an inline fragment, we need to add it to the last active field's type branches.
              T.must(@active_path.last).add_type_branch(field)
            end
          end
          @active_path << field
        end

        # Called when exiting a field. Removes the most recently entered field from the active path.
        sig { returns(T.nilable(Field)) }
        def exit_field
          @active_path.pop
        end

        # Returns the current active field, i.e. the last field in the active path.
        sig { returns(T.nilable(Field)) }
        def active_field
          @active_path.last
        end

        # Constructs the final FieldTree from the accumulated root fields.
        sig { returns(FieldTree) }
        def build
          # Convert each root field to a FieldNode
          root_nodes = @root_fields.map do |root_field|
            FieldTreeNode.new(root_field, nil)
          end
          FieldTree.new(root_nodes)
        end
      end
    end
  end
end
