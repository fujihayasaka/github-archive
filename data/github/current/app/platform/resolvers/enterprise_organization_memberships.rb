# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseOrganizationMemberships < Resolvers::Base
      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::OrganizationOrder,
        "Ordering options for organizations returned from the connection.",
        required: false, default_value: { field: "login", direction: "ASC" }
      argument :role, Enums::EnterpriseUserAccountMembershipRole,
        "The role of the user in the enterprise organization.",
        required: false

      type Platform::Connections::EnterpriseOrganizationMembership, null: false

      def resolve(query: nil, order_by: nil, role: nil)
        Promise.all([
          object.async_user,
          object.async_business,
        ]).then do
          object.enterprise_organizations \
            context[:viewer],
            query: query,
            order_by_field: order_by&.dig(:field),
            order_by_direction: order_by&.dig(:direction),
            org_member_type: ::BusinessUserAccount.org_member_type_from_role(role)
        end
      end
    end
  end
end
