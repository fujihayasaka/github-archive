# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseSupportEntitlements < Resolvers::Base
      type Connections.define(Unions::EnterpriseMember, edge_type: Edges::EnterpriseMember), null: false

      argument :order_by, Inputs::EnterpriseMemberOrder,
        "Ordering options for support entitlement users returned from the connection.",
        required: false, default_value: { field: "login", direction: "ASC" }

      def resolve(order_by: nil)
        order_field = order_by&.dig(:field) || "login"
        order_direction = order_by&.dig(:direction) || "ASC"
        object.support_entitlees.order("#{order_field} #{order_direction}")
      end
    end
  end
end
