module API
  module Connections
    class AbstractRepositoryDependents < GraphQL::Types::Relay::BaseConnection
      edge_type(API::Types::AbstractDependent.edge_type)

      field :total_count, Integer, null: false

      def total_count
        owner_id = object.arguments[:owner_id]
        Queries::AbstractRepositoryDependentsQuery.new(
          depends_on: object.parent,
          github_owner_id: owner_id,
        ).dependent_count
      end
    end
  end
end
