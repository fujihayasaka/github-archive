# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable
    class SternBrocotTree
      # Represents a node in the Stern-Brocot tree.
      #
      # This class is only used in tests in order to demonstrate
      # the structure of the tree; it not used in production code.
      class Node < T::Struct
        const :value, Rational
        prop :left_child, T.nilable(Node)
        prop :right_child, T.nilable(Node)

        Stack = T.type_alias { T::Array[Node] }

        sig { params(traversal: Traversal).returns(T::Array[Rational]) }
        def flatten(traversal: Traversal::LevelOrder)
          case traversal
          when Traversal::PreOrder then traverse_with([self])
          when Traversal::LevelOrder then traverse_with(Queue.new([self]))
          else T.absurd(traversal)
          end
        end

        sig { params(queue_like: T.any(Stack, Queue)).returns(T::Array[Rational]) }
        private def traverse_with(queue_like)
          nodes = T.let([], T::Array[Rational])

          while !queue_like.empty?
            curr = T.cast(queue_like.pop, Node)
            nodes << curr.value
            queue_like << T.must(curr.left_child) if curr.left_child
            queue_like << T.must(curr.right_child) if curr.right_child
          end

          nodes
        end
      end
    end
  end
end
