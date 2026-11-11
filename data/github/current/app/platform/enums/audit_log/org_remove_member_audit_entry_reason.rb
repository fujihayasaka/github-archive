# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    module AuditLog
      class OrgRemoveMemberAuditEntryReason < Platform::Enums::Base
        description "The reason a member was removed from an Organization."

        REASONS = {
          ::Organization::RemovedMemberNotification::TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE => "2fa non-compliance",
          ::Organization::RemovedMemberNotification::SAML_EXTERNAL_IDENTITY_MISSING => "SAML external identity missing",
          ::Organization::RemovedMemberNotification::USER_ACCOUNT_DELETED => "user account has been deleted",
          ::Organization::RemovedMemberNotification::TWO_FACTOR_ACCOUNT_RECOVERY => "two factor account recovery",
          "saml_sso_enforcement_requires_external_identity" => "SAML external identity missing",
        }.with_indifferent_access.freeze

        value "TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE", "The organization required 2FA of its billing managers and this user did not have 2FA enabled.", value: "two_factor_requirement_non_compliance"
        value "SAML_EXTERNAL_IDENTITY_MISSING", "SAML external identity missing", value: "saml_external_identity_missing"
        value "SAML_SSO_ENFORCEMENT_REQUIRES_EXTERNAL_IDENTITY", "SAML SSO enforcement requires an external identity", value: "saml_sso_enforcement_requires_external_identity"
        value "USER_ACCOUNT_DELETED", "User account has been deleted", value: "user_account_deleted"
        value "TWO_FACTOR_ACCOUNT_RECOVERY", "User was removed from organization during account recovery", value: "two_factor_account_recovery"
      end
    end
  end
end
