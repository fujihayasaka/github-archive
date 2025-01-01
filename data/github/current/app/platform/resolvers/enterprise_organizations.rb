# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseOrganizations < Resolvers::Base
      type Connections.define(Objects::Organization), null: false
      argument :query, String, "The search string to look for.", required: false
      argument :viewer_organization_role,
        Enums::RoleInOrganization,
        "The viewer's role in an organization.",
        required: false
      argument :order_by, Inputs::OrganizationOrder,
        "Ordering options for organizations returned from the connection.",
        required: false, default_value: { field: "login", direction: "ASC" }

      def resolve(query: nil, viewer_organization_role: nil, order_by: nil)
        ensure_business_not_suspended!(object, message: "Cannot list organizations for #{object.slug}")
        ensure_business_payment_completed!(object)
        business_full_plan_required!(object)

        object.filtered_organizations \
          viewer: @context[:viewer],
          viewer_role: viewer_role(viewer_organization_role),
          query: query,
          order_by_field: order_by&.dig(:field) || "login",
          order_by_direction: order_by&.dig(:direction) || "ASC"
      end

      private

      def viewer_role(role)
        # Platform::Enums::RoleInOrganization returns "direct_member" but
        # ::Business#filtered_organizations expects "member"
        return "member" if role == "direct_member"
        return role if %w(owner unaffiliated).include?(role)
        nil
      end
    end
  end
end
