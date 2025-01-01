# typed: true
# frozen_string_literal: true

module TokenRevocation
  module Helper
    PAT_CREDENTIAL = :PERSONAL_ACCESS_TOKEN
    FG_PAT_CREDENTIAL = :FINE_GRAINED_PERSONAL_ACCESS_TOKEN
    # Public: Sends a mailer to the owner of the credential that it has been revoked from the API
    #
    # owner - The owner of the credential to notify
    # credential_name - The credential name to notify the user about
    # credential_type - The type of credential that was revoked (eg. :PERSONAL_ACCESS_TOKEN)
    #
    def self.notify_owner_of_revoked_credential(owner, credential_name, credential_type)
      return unless GitHub.flipper[:credential_revocation_api].enabled?

      # If the user is nil, we can't notify them
      if owner.nil?
        GitHub.dogstats.increment("revoked_credential.notify", tags: ["result:failed", "reason:missing_owner", "type:#{credential_type}"])
        return
      end

      if credential_type.present?
        case credential_type
        when PAT_CREDENTIAL, FG_PAT_CREDENTIAL
          RevokedCredentialMailer.personal_access_token_revoked(owner, credential_name, type: credential_type).deliver_later
        else
          GitHub.dogstats.increment("revoked_credential.notify", tags: ["result:failed", "reason:invalid_type", "type:#{credential_type}"])
          return
        end

        GitHub.dogstats.increment("revoked_credential.notify", tags: ["result:queued", "type:#{credential_type}"])
      end
    end

    # Public: Determines if the appropriate FFs are enabled to use the credential revocation API, including the token revocation job
    # Returns true if the main FF is enabled OR if the env is review lab and the review lab FF is enabled
    # Returns false otherwise
    def self.credential_revocation_enabled?
      return true if GitHub.flipper[:credential_revocation_api].enabled?
      return true if GitHub.review_lab? && GitHub.flipper[:credential_revocation_api_review_lab].enabled?
      false
    end
  end
end
