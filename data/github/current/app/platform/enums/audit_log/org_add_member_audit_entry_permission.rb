# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OrgAddMemberAuditEntryPermission < Platform::Enums::Base
        description "The permissions available to members on an Organization."

        value "READ", "Can read and clone repositories.", value: "read"
        value "ADMIN", "Can read, clone, push, and add collaborators to repositories.", value: "admin"
      end
    end
  end
end
