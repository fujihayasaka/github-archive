# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class RepositoryActivities < Resolvers::Base
      type Connections.define(Objects::Activity), null: false

      argument :order_by, Inputs::ActivityOrder, "Ordering options for activities returned from the connection.", required: false, default_value: { field: "timestamp", direction: "DESC" }
      argument :filter_by, Inputs::ActivityFilters, "Filtering options for activities returned from the connection.", required: false

      def resolve(**arguments)
        ConnectionWrappers::RepositoryActivities.new(
          context:,
          field:,
          parent: object,
          first: arguments[:first],
          last: arguments[:last],
          after: arguments[:after],
          before: arguments[:before],
          arguments: arguments
        )
      end
    end
  end
end
