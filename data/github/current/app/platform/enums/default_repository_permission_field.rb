# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class DefaultRepositoryPermissionField < Platform::Enums::Base
      description "The possible base permissions for repositories."

      value "NONE", "No access", value: "none"
      value "READ", "Can read repos by default", value: "read"
      value "WRITE", "Can read and write repos by default", value: "write"
      value "ADMIN", "Can read, write, and administrate repos by default", value: "admin"
    end
  end
end
