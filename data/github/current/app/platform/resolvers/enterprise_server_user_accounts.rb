# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseServerUserAccounts < Resolvers::Base
      argument :order_by, Inputs::EnterpriseServerUserAccountOrder,
        "Ordering options for Enterprise Server user accounts returned from the connection.",
        required: false, default_value: { field: "login", direction: "ASC" }

      type Connections.define(Objects::EnterpriseServerUserAccount), null: false

      def resolve(order_by: nil)
        accounts = object.user_accounts
        accounts = apply_order_by(accounts, order_by)
      end

      def apply_order_by(scope, order_by)
        return scope if order_by.nil?
        scope.order("enterprise_installation_user_accounts.#{order_by[:field]} #{order_by[:direction]}")
      end
    end
  end
end
