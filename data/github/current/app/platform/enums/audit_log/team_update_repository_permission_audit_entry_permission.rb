# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class TeamUpdateRepositoryPermissionAuditEntryPermission < Platform::Enums::Base
        description "The permissions a team has on a repository."
        visibility :under_development

        value "PULL", "Can read and clone the repository.", value: "pull"
        value "PUSH", "Can read, clone and push the repository.", value: "push"
        value "ADMIN", "Can read, clone, push, and add collaborators to the repository.", value: "admin"
      end
    end
  end
end
