module API
  module Edges
    class VulnerableVersionRangeEdge < GraphQL::Relay::Edge
      def contained?
        self.node.requirements_set.contain?(self.parent.requirements_set)
      end
    end
  end
end
