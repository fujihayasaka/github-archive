# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class RoleInOrganization < Platform::Enums::Base
      description "Possible roles a user may have in relation to an organization."

      value "OWNER", "A user with full administrative access to the organization.", value: "owner"
      value "DIRECT_MEMBER", "A user who is a direct member of the organization.", value: "direct_member"
      value "UNAFFILIATED", "A user who is unaffiliated with the organization.", value: "unaffiliated"
    end
  end
end
