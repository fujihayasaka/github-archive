# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class TeamMembershipState < Platform::Enums::Base
      description "The possible team membership state values."
      visibility :internal

      value "LEAVE", "The user can leave the team.", value: "leave"
      value "LEAVE_DISABLED", "The user can not leave the team.", value: "leave_disabled"
      value "JOIN", "The user can join the team.", value: "join"
      value "REQUEST_PENDING", "The user has requested to join the team.", value: "request_pending"
      value "REQUEST_MEMBERSHIP", "The user can request to join the team.", value: "request_membership"
      value "LDAP_MAPPED", "The user must be added or removed from the mapped LDAP Group", value: "ldap_mapped"
    end
  end
end
