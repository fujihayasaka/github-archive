# typed: true
# frozen_string_literal: true

module Platform
  module Edges
    class OrganizationEnterpriseOwner < Edges::Base
      node_type Objects::User
      description "An enterprise owner in the context of an organization that is part of the enterprise."

      field :organization_role, Enums::RoleInOrganization, description: "The role of the owner with respect to the organization.", null: false

      def organization_role
        org = object.parent
        user = object.node
        if org.adminable_by?(user)
          T.must(Enums::RoleInOrganization.values["OWNER"]).value
        elsif org.direct_or_team_member?(user)
          T.must(Enums::RoleInOrganization.values["DIRECT_MEMBER"]).value
        else
          T.must(Enums::RoleInOrganization.values["UNAFFILIATED"]).value
        end
      end
    end
  end
end
