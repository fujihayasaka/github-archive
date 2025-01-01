# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Stargazer < Connections::Base
      total_count_field

      def total_count
        if @object.respond_to?(:count)
          @object.count
        elsif @object.arguments.values.compact.empty? && @object.parent.is_a?(::Repository)
          @object.parent.stargazer_count
        else
          @object.total_count
        end
      end

      # custom nodes implementation to support custom stargazer edge
      def nodes
        @object.edge_nodes.then do |nodes|
          ::Promise.all(nodes.map(&:async_user))
        end
      end
    end
  end
end
