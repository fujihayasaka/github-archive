# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class StarredRepository < Connections::Base
      total_count_field

      field :is_over_limit, Boolean,
        visibility: :public,
        null: false,
        description: "Is the list of stars for this user truncated? This is true for users that have many stars."
      def is_over_limit
        return false unless @object.is_a?(Platform::ConnectionWrappers::StarredRepositories)

        @object.over_limit?
      end

      # Custom `nodes` implementation if we're not coming from search
      def nodes
        return @object.edge_nodes if @object.edge_nodes.is_a?(Array)

        @object.edge_nodes.then do |nodes|
          Promise.all(nodes.map { |value| Loaders::ActiveRecord.load(::Repository, value.starrable_id) })
        end
      end
    end
  end
end
