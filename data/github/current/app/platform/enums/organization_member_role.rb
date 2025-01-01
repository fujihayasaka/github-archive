# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class OrganizationMemberRole < Platform::Enums::Base
      description "The possible roles within an organization for its members."

      value "MEMBER", "The user is a member of the organization.", value: "member"
      value "ADMIN", "The user is an administrator of the organization.", value: "admin"
    end
  end
end
