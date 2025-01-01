# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class ReactingUser < Connections::Base
      total_count_field

      def total_count
        parent.total_count
      end

      # custom nodes implementation to support custom reacting user edge
      def nodes
        @object.edge_nodes.then do |user_ids|
          ::Promise.all(user_ids.map do |user_id|
            Loaders::ActiveRecord.load(::User, user_id)
          end)
        end
      end
    end
  end
end
