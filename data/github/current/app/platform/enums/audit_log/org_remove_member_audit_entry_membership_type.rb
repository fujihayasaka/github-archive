# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OrgRemoveMemberAuditEntryMembershipType < Platform::Enums::Base
        description "The type of membership a user has with an Organization."
        value "SUSPENDED", "A suspended member.", value: "suspended"
        value "DIRECT_MEMBER", "A direct member is a user that is a member of the Organization.", value: "direct_member"
        value "ADMIN", "Organization owners have full access and can change several settings, including the names of repositories that belong to the Organization and Owners team membership. In addition, organization owners can delete the organization and all of its repositories.", value: "admin"
        value "BILLING_MANAGER", "A billing manager is a user who manages the billing settings for the Organization, such as updating payment information.", value: "billing_manager"
        value "UNAFFILIATED", "An unaffiliated collaborator is a person who is not a member of the Organization and does not have access to any repositories in the Organization.", value: "unaffiliated"
        value "OUTSIDE_COLLABORATOR", "An outside collaborator is a person who isn't explicitly a member of the Organization, but who has Read, Write, or Admin permissions to one or more repositories in the organization.", value: "outside_collaborator"
      end
    end
  end
end
