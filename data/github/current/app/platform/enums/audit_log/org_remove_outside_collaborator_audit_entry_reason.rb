# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OrgRemoveOutsideCollaboratorAuditEntryReason < Platform::Enums::Base
        description "The reason an outside collaborator was removed from an Organization."

        REASONS = {
          ::Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE => "2fa non-compliance",
          ::Organization::RemovedMemberNotification::SAML_EXTERNAL_IDENTITY_MISSING => "SAML external identity missing",
        }.with_indifferent_access.freeze

        value "TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE", "The organization required 2FA of its billing managers and this user did not have 2FA enabled.", value: "two_factor_requirement_non_compliance"
        value "SAML_EXTERNAL_IDENTITY_MISSING", "SAML external identity missing", value: "saml_external_identity_missing"
      end
    end
  end
end
