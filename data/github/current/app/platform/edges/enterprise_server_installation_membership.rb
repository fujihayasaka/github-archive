# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class EnterpriseServerInstallationMembership < Edges::Base
      node_type Objects::EnterpriseServerInstallation
      description "An Enterprise Server installation that a user is a member of."

      field :role, Enums::EnterpriseUserAccountMembershipRole, description: "The role of the user in the enterprise membership.", null: false
      def role
        business_user_account = object.parent
        enterprise_installation = object.node

        business_user_account.async_enterprise_installation_user_accounts.then do |server_user_accounts|
          account = server_user_accounts.find { |account| account.enterprise_installation_id == enterprise_installation.id }
          if account.site_admin?
            T.must(Enums::EnterpriseUserAccountMembershipRole.values["OWNER"]).value
          else
            T.must(Enums::EnterpriseUserAccountMembershipRole.values["MEMBER"]).value
          end
        end
      end
    end
  end
end
