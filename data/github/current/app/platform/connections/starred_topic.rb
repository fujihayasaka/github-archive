# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class StarredTopic < Connections::Base
      visibility :under_development

      total_count_field

      # Custom `nodes` implementation if we're not coming from search
      def nodes
        return @object.edge_nodes if @object.edge_nodes.is_a?(Array)

        @object.edge_nodes.then do |nodes|
          Promise.all(
            nodes.map do |value|
              Loaders::ActiveRecord.load(::Topic, value.starrable_id)
            end,
          )
        end
      end
    end
  end
end
