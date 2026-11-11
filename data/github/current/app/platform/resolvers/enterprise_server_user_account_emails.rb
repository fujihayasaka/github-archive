# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseServerUserAccountEmails < Resolvers::Base
      argument :order_by, Inputs::EnterpriseServerUserAccountEmailOrder,
        "Ordering options for Enterprise Server user account emails returned from the connection.",
        required: false, default_value: { field: "email", direction: "ASC" }

      type Connections.define(Objects::EnterpriseServerUserAccountEmail), null: false

      def resolve(order_by: nil)
        emails = object.emails
        emails = apply_order_by(emails, order_by)
      end

      def apply_order_by(scope, order_by)
        return scope if order_by.nil?
        scope.order("enterprise_installation_user_account_emails.#{order_by[:field]} #{order_by[:direction]}")
      end
    end
  end
end
