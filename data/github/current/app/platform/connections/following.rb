# typed: true
# frozen_string_literal: true

module Platform
  module Connections
    class Following < Connections::Base
      edge_type(Edges::User, node_type: Objects::User)
      total_count_field

      def total_count
        if @object.parent.is_a? Platform::Models::AccountStafftoolsInfo
          @object.items.count
        elsif @object.parent
          @object.parent.following_count(viewer: context[:viewer])
        else
          @object.items.count
        end
      end

      def nodes
        @object.edge_nodes.then do |followings|
          user_promises = followings.map(&:async_following) # followed user
          Promise.all(user_promises)
        end
      end
    end
  end
end
