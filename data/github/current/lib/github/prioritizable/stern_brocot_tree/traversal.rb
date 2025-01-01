# typed: strict
# frozen_string_literal: true

module GitHub
  module Prioritizable
    class SternBrocotTree
      # Options for different ways in which we can traverse the
      # Stern-Brocot tree starting from the root node.
      #
      # This class is only used in tests in order to demonstrate
      # the structure of the tree; it not used in production code.
      class Traversal < T::Enum
        enums do
          PreOrder = new
          LevelOrder = new
        end
      end
    end
  end
end
