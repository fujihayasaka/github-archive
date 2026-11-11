# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OrgRemoveOutsideCollaboratorAuditEntryMembershipType < Platform::Enums::Base
        description "The type of membership a user has with an Organization."

        value "OUTSIDE_COLLABORATOR", "An outside collaborator is a person who isn't explicitly a member of the Organization, but who has Read, Write, or Admin permissions to one or more repositories in the organization.", value: "outside_collaborator"
        value "UNAFFILIATED", "An unaffiliated collaborator is a person who is not a member of the Organization and does not have access to any repositories in the organization.", value: "unaffiliated"
        value "BILLING_MANAGER", "A billing manager is a user who manages the billing settings for the Organization, such as updating payment information.", value: "billing_manager"
      end
    end
  end
end
