# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseMembers < Resolvers::Base
      argument :organization_logins, [String], "Only return members within the organizations with these logins", required: false
      argument :query, String, "The search string to look for.", required: false
      argument :order_by, Inputs::EnterpriseMemberOrder,
        "Ordering options for members returned from the connection.",
        required: false, default_value: { field: "login", direction: "ASC" }
      argument :role, Enums::EnterpriseUserAccountMembershipRole,
        "The role of the user in the enterprise organization or server.",
        required: false
      argument :deployment, Enums::EnterpriseUserDeployment, "Only return members within the selected GitHub Enterprise deployment", required: false
      argument :license, Enums::EnterpriseLicenseType, "Only return members with the selected user license type", required: false
      argument :has_two_factor_enabled, Boolean,
        "Only return members with this two-factor authentication status. Does not include members who only have an account on a GitHub Enterprise Server instance.",
        required: false,
        default_value: nil

      type Connections.define(Unions::EnterpriseMember, edge_type: Edges::EnterpriseMember), null: false

      def resolve(organization_logins: nil, query: nil, order_by: nil, role: nil, deployment: nil, license: nil, has_two_factor_enabled: nil)
        ensure_business_can_use_api! \
          object,
          message: "Cannot list members for #{object.slug}"

        object.async_organizations.then do
          object.async_external_provider.then do
            object.filtered_members \
              context[:viewer],
              organization_logins: organization_logins,
              query: query,
              order_by_field: order_by&.dig(:field) || "login",
              order_by_direction: order_by&.dig(:direction) || "ASC",
              role: role,
              deployment: deployment,
              license: license,
              two_factor: user_two_factor_statuses_argument(has_two_factor_enabled)
          end
        end
      end

      def user_two_factor_statuses_argument(has_two_factor_enabled)
        case has_two_factor_enabled
        when true
          :enabled
        when false
          :disabled
        else
          nil
        end
      end

    end
  end
end
