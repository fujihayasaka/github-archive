# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class EnterpriseAdministrator < Edges::Base
      node_type Objects::User
      description "A User who is an administrator of an enterprise."

      field :role, Enums::EnterpriseAdministratorRole, description: "The role of the administrator.", null: false

      def role
        business = object.parent
        user = object.node
        if business.owner?(user)
          T.must(Enums::EnterpriseAdministratorRole.values["OWNER"]).value
        elsif business.billing.manager?(user)
          T.must(Enums::EnterpriseAdministratorRole.values["BILLING_MANAGER"]).value
        end
      end
    end
  end
end
