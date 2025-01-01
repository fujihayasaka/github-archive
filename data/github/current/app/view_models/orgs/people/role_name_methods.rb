# typed: true
# frozen_string_literal: true

module Orgs::People::RoleNameMethods
  # Public: What is the human-readable name of each role within an organization?
  #
  # Returns a string.
  def role_name
    Organization::Role.name_for_type T.unsafe(self).role.type
  end
end
