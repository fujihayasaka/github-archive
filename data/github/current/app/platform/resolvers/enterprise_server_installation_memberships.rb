# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseServerInstallationMemberships < Resolvers::Base
      type Connections.define(Objects::EnterpriseServerInstallation,
        name: "EnterpriseServerInstallationMembership",
        edge_type: Edges::EnterpriseServerInstallationMembership), null: false

      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::EnterpriseServerInstallationOrder,
        "Ordering options for installations returned from the connection.",
        required: false, default_value: { field: "host_name", direction: "ASC" }
      argument :role, Enums::EnterpriseUserAccountMembershipRole,
        "The role of the user in the installation.",
        required: false

      def resolve(query: nil, order_by: nil, role: nil)
        Promise.all([
            object.async_business,
            object.async_enterprise_installation_user_accounts,
        ]).then do |_business, _|
          @object.user_enterprise_installations(
            query: query,
            order_by_field: order_by&.dig(:field),
            order_by_direction: order_by&.dig(:direction),
            role: role,
          )
        end
      end
    end
  end
end
