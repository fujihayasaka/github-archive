# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OrgUpdateMemberRepositoryCreationPermissionAuditEntryVisibility < Platform::Enums::Base
        description "The permissions available for repository creation on an Organization."

        value "ALL", "All organization members are restricted from creating any repositories.", value: "all"
        value "PUBLIC", "All organization members are restricted from creating public repositories.", value: "public"
        value "NONE", "All organization members are allowed to create any repositories.", value: "none"
        value "PRIVATE", "All organization members are restricted from creating private repositories.", value: "private"
        value "INTERNAL", "All organization members are restricted from creating internal repositories.", value: "internal"
        value "PUBLIC_INTERNAL", "All organization members are restricted from creating public or internal repositories.", value: "public_internal"
        value "PRIVATE_INTERNAL", "All organization members are restricted from creating private or internal repositories.", value: "private_internal"
        value "PUBLIC_PRIVATE", "All organization members are restricted from creating public or private repositories.", value: "public_private"
      end
    end
  end
end
