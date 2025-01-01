# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectPermission < Platform::Enums::Base
      description "The access level to a project"
      visibility :internal

      value "ADMIN", "Can read, write, and modify permissions", value: "admin"
      value "WRITE", "Can read and write", value: "write"
      value "READ", "Can read", value: "read"
      value "NONE", "Cannot read or do anything else", value: "none"
    end
  end
end
