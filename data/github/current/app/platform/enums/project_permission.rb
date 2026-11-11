# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ProjectPermission < Platform::Enums::Base
      description "The access level to a project"
      visibility :internal

      value "ADMIN", "Can read, write, and modify permissions", value: "admin", deprecated: Helpers::ProjectDeprecation::Notice
      value "WRITE", "Can read and write", value: "write", deprecated: Helpers::ProjectDeprecation::Notice
      value "READ", "Can read", value: "read", deprecated: Helpers::ProjectDeprecation::Notice
      value "NONE", "Cannot read or do anything else", value: "none", deprecated: Helpers::ProjectDeprecation::Notice
    end
  end
end
