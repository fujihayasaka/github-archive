# typed: true
# frozen_string_literal: true

module Platform
  module Resolvers
    class EnterpriseAdmins < Resolvers::Base

      type Connections::EnterpriseAdministrator, null: false

      argument :organization_logins, [String], "Only return members within the organizations with these logins", required: false
      argument :query, String, "The search string to look for.", required: false
      argument :role, Enums::EnterpriseAdministratorRole, "The role to filter by.", required: false
      argument :order_by, Inputs::EnterpriseMemberOrder,
        "Ordering options for administrators returned from the connection.",
        required: false, default_value: { field: "login", direction: "ASC" }
      argument :has_two_factor_enabled, Boolean,
        "Only return administrators with this two-factor authentication status.",
        required: false, default_value: nil

      def resolve(query: nil, order_by: nil, role: nil, organization_logins: nil, has_two_factor_enabled: nil)
        enterprise = object.is_a?(Platform::Models::AccountStafftoolsInfo) ? object.account : object
        ensure_business_can_use_api!(enterprise) unless context[:viewer].site_admin?

        enterprise.admins \
          query: query,
          order_by_field: order_by&.dig(:field),
          order_by_direction: order_by&.dig(:direction),
          role: role_from_enum_value(role),
          organization_logins: organization_logins,
          two_factor: user_two_factor_statuses_argument(has_two_factor_enabled)
      end

      private

      def role_from_enum_value(role)
        return nil unless role.present?

        case role
        when T.must(Platform::Enums::EnterpriseAdministratorRole.values["OWNER"]).value
          :owner
        when T.must(Platform::Enums::EnterpriseAdministratorRole.values["BILLING_MANAGER"]).value
          :billing_manager
        else
          raise Platform::Errors::Internal, "Unexpected role: #{role}"
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
