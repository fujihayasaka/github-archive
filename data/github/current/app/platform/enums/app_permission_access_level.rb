# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AppPermissionAccessLevel < Platform::Enums::Base

      description "The level of access that a GitHub App has to a resource"
      visibility :under_development

      value "ADMIN", "Can read, write, and admin", value: "admin"
      value "WRITE", "Can read and write",         value: "write"
      value "READ",  "Can read",                   value: "read"
    end
  end
end
