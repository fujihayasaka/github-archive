# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OrgUpdateDefaultRepositoryPermissionAuditEntryPermission < Platform::Enums::Base
        description "The default permission a repository can have in an Organization."

        value "READ", "Can read and clone repositories.", value: "read"
        value "WRITE", "Can read, clone and push to repositories.", value: "write"
        value "ADMIN", "Can read, clone, push, and add collaborators to repositories.", value: "admin"
        value "NONE", "No default permission value.", value: "none"
      end
    end
  end
end
