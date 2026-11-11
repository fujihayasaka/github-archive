# typed: strict
# frozen_string_literal: true

module Search
  module Memex
    module Nodes
      # Represents a parenthesized group of query terms, e.g. `(is:open OR label:bug)`.
      #
      # Children are AND-combined within the group using the same deep-merge strategy as Root.
      # The group itself participates in the outer query as a self-contained clause, which allows
      # expressions like `(is:open OR label:bug) AND assignee:@me`.
      #
      # Example query: "(is:open OR label:bug) AND status:Ready"
      # Produces two Root children:
      #   - ParenGroup([OrGroup(is:open, label:bug)]) → compiles to bool.should wrapped in bool.must
      #   - FieldValueQualifier(status:Ready) → flat filter merged normally
      class ParenGroup < Node
        include DeepMergeHelpers

        sig { returns(T::Array[Node]) }
        attr_reader :children

        sig { params(children: T::Array[Node]).void }
        def initialize(children:)
          super()
          @children = T.let(children, T::Array[Node])
        end

        sig { override.params(context: Search::Memex::Context).returns(T::Hash[T.untyped, T.untyped]) }
        def compile(context)
          @children
            .map { |node| node.compile_as_must_query(context) }
            .inject({}) { |acc, result| deep_merge_query(acc, result) }
        end

        sig { override.returns(String) }
        def query_string
          "(#{@children.map(&:query_string).join(" ")})"
        end

        sig { override.returns(T::Boolean) }
        def sub_issue_filter?
          @children.any?(&:sub_issue_filter?)
        end
      end
    end
  end
end
