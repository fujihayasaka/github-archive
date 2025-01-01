# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OauthApplicationCreateAuditEntryState < Platform::Enums::Base
        description "The state of an OAuth application when it was created."

        value "ACTIVE", "The OAuth application was active and allowed to have OAuth Accesses.", value: "active"
        value "SUSPENDED", "The OAuth application was suspended from generating OAuth Accesses due to abuse or security concerns.", value: "suspended"
        value "PENDING_DELETION", "The OAuth application was in the process of being deleted.", value: "pending_deletion"
      end
    end
  end
end
