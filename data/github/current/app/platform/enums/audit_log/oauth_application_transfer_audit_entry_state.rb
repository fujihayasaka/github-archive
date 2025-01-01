# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OauthApplicationTransferAuditEntryState < Platform::Enums::Base
        description "The state of an OAuth Application when its tokens were revoked."
        visibility :under_development

        value "ACTIVE", "The OAuth Application was active and allowed to have OAuth Accesses.", value: "active"
        value "SUSPENDED", "The OAuth Application was suspended from generating OAuth Accesses due to abuse or security concerns.", value: "suspended"
        value "PENDING_DELETION", "The OAuth Application was in the process of being deleted.", value: "pending_deletion"
      end
    end
  end
end
