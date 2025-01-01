# typed: true
# frozen_string_literal: true

# Stores members removed from Organization due to 2FA or SAML enforcement.
# Expires in 90 days.
#
# Note: Only one notification per org/user combination can exist. A user cannot
# be notified of removal for both reasons at once.
class Organization
  class RemovedMemberNotification
    TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE = "two_factor_requirement_non_compliance".freeze
    SAML_EXTERNAL_IDENTITY_MISSING        = "saml_external_identity_missing".freeze
    TWO_FACTOR_ACCOUNT_RECOVERY           = "two_factor_account_recovery".freeze
    USER_ACCOUNT_DELETED                  = "user_account_deleted".freeze

    # Update the hydro github.v1.MembershipUpdate hydro schema if these values change.
    VALID_REASONS = [
      TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE,
      SAML_EXTERNAL_IDENTITY_MISSING,
      TWO_FACTOR_ACCOUNT_RECOVERY,
      USER_ACCOUNT_DELETED,
    ]

    attr_reader :organization, :user

    def initialize(organization, user)
      @organization = organization
      @user = user
    end

    # Public: Dismiss the current notification
    #
    # Returns a boolean (true if the notification existed and was dismissed,
    # false if either the notification didn't exist or there was an error)
    def dismiss
      return false unless valid_argument_types?
      GitHub.kv.del(org_user_key) # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    def add_two_factor_requirement_non_compliance
      add(reason: TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE)
    end

    def two_factor_requirement_non_compliance?
      exists?(reason: TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE)
    end

    def add_saml_external_identity_missing
      add(reason: SAML_EXTERNAL_IDENTITY_MISSING)
    end

    def saml_external_identity_missing?
      exists?(reason: SAML_EXTERNAL_IDENTITY_MISSING)
    end

    private

    def add(reason:)
      return false unless valid_argument_types?(reason: reason)
      GitHub.kv.set(org_user_key, reason.to_s, expires: 90.days.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    def exists?(reason:)
      return false unless valid_argument_types?(reason: reason)
      stored_value == reason
    end

    def stored_value
      GitHub.kv.get(org_user_key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
    end

    def org_user_key
      "organization-membership-removed.#{organization.id}:#{user.id}"
    end

    def valid_argument_types?(reason: TWO_FACTOR_REQUIREMENT_NON_COMPLIANCE)
      organization.is_a?(Organization) &&
        user.is_a?(User) &&
        VALID_REASONS.include?(reason)
    end
  end
end
