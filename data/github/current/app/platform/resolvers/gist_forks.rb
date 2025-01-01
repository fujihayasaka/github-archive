# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class GistForks < Resolvers::Base

      type Connections.define(Objects::Gist), null: false

      def resolve(**arguments)
        context[:permission].async_can_list_gist_forks?(object).then do |can_list_gist_forks|
          next [] unless can_list_gist_forks

          scope = @object.visible_forks

          if order_by = arguments[:order_by]
            scope = scope.order("#{scope.table_name}.#{order_by[:field]} #{order_by[:direction]}")
          end

          scope
        end
      end
    end
  end
end
