# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationInvitationRole < Platform::Enums::Base
      description "The possible organization invitation roles."

      value "DIRECT_MEMBER", "The user is invited to be a direct member of the organization.", value: "direct_member"
      value "ADMIN", "The user is invited to be an admin of the organization.", value: "admin"
      value "BILLING_MANAGER", "The user is invited to be a billing manager of the organization.", value: "billing_manager"
      value "REINSTATE", "The user's previous role will be reinstated.", value: "reinstate"
    end
  end
end
