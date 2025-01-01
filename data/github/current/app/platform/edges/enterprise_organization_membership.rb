# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class EnterpriseOrganizationMembership < Edges::Base
      node_type Objects::Organization
      description "An enterprise organization that a user is a member of."

      field :role, Enums::EnterpriseUserAccountMembershipRole, description: "The role of the user in the enterprise membership.", null: false
      def role
        user_account = object.parent
        org = object.node

        user_account.async_user.then do |user|
          types = org.role_of(user).types
          if types.include?(:admin)
            T.must(Enums::EnterpriseUserAccountMembershipRole.values["OWNER"]).value
          elsif types.include?(:direct_member)
            T.must(Enums::EnterpriseUserAccountMembershipRole.values["MEMBER"]).value
          end
        end
      end
    end
  end
end
