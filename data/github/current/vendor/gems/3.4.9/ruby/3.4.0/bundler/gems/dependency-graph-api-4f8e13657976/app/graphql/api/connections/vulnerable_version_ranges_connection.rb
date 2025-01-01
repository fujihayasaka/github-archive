module API
  module Connections
    class VulnerableVersionRangeEdgeType < GraphQL::Types::Relay::BaseEdge
      node_type(API::Types::VulnerableVersionRange)

      field :is_contained, Boolean, null: false, method: :contained?
    end

    class VulnerableVersionRangesConnection < GraphQL::Types::Relay::BaseConnection
      edge_type(VulnerableVersionRangeEdgeType, edge_class: API::Edges::VulnerableVersionRangeEdge)
    end
  end
end
