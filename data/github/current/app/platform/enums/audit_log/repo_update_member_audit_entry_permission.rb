# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class RepoUpdateMemberAuditEntryPermission < Platform::Enums::Base
        description "The access level to a repository"
        visibility :under_development

        value "ADMIN", "Can read, clone, push, and add collaborators", value: "admin"
        value "WRITE", "Can read, clone and push", value: "write"
        value "READ", "Can read and clone", value: "read"
      end
    end
  end
end
