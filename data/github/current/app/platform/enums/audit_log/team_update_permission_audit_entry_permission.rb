# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class TeamUpdatePermissionAuditEntryPermission < Platform::Enums::Base
        description "Permissions available for members of a team."
        visibility :under_development

        value "PULL", "Can read and clone repositories.", value: "pull"
        value "PUSH", "Can read, clone and push to repositories.", value: "push"
        value "ADMIN", "Can read, clone, push, and add collaborators to repositories.", value: "admin"
      end
    end
  end
end
