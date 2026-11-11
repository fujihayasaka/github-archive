# typed: true
# frozen_string_literal: true

module TokenRevocation
  module Helper
    PAT_CREDENTIAL = :PERSONAL_ACCESS_TOKEN
    FG_PAT_CREDENTIAL = :FINE_GRAINED_PERSONAL_ACCESS_TOKEN
    OAUTH_APP_TOKEN_CREDENTIAL = :OAUTH_APP_TOKEN
    GH_APP_U2S_CREDENTIAL = :GH_APP_USER_TO_SERVER_TOKEN
    GH_APP_S2S_CREDENTIAL = :GH_APP_SERVER_TO_SERVER_TOKEN
    GH_APP_REFRESH_TOKEN_CREDENTIAL = :GH_APP_REFRESH_TOKEN

    # Public: Sends a mailer to the owner of the credential that it has been revoked from the API
    #
    # owner - The owner of the credential to notify
    # credential_name - The credential name to notify the user about
    # credential_type - The type of credential that was revoked (eg. :PERSONAL_ACCESS_TOKEN)
    # scopes - Optional list of scopes the OAuth app token had (only used for OAUTH_APP_TOKEN_CREDENTIAL)
    #
    def self.notify_owner_of_revoked_credential(owner, credential_name, credential_type, scopes: nil)
      return unless TokenRevocation::Helper.credential_revocation_enabled?

      # If the user is nil, we can't notify them
      if owner.nil?
        GitHub.dogstats.increment("revoked_credential.notify", tags: ["result:failed", "reason:missing_owner", "type:#{credential_type}"])
        return
      end

      if credential_type.present?
        case credential_type
        when PAT_CREDENTIAL, FG_PAT_CREDENTIAL
          RevokedCredentialMailer.personal_access_token_revoked(owner, credential_name, type: credential_type).deliver_later
        when OAUTH_APP_TOKEN_CREDENTIAL
          RevokedCredentialMailer.oauth_token_revoked(owner, credential_name, scopes: scopes).deliver_later
        when GH_APP_U2S_CREDENTIAL
          RevokedCredentialMailer.github_app_user_to_server_token_revoked(owner, credential_name).deliver_later
        when GH_APP_S2S_CREDENTIAL
          RevokedCredentialMailer.github_app_server_to_server_token_revoked(owner, credential_name).deliver_later
        when GH_APP_REFRESH_TOKEN_CREDENTIAL
          RevokedCredentialMailer.github_app_refresh_token_revoked(owner, credential_name).deliver_later
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
      return true if FeatureFlag.vexi.enabled?(:credential_revocation_api, default: false)
      return true if enabled_for_review_lab?
      false
    end

    # Public: Determines if OAuth app token revocation is enabled
    # Returns true if the credential_revocation_oauth_app_tokens FF is enabled,
    # or if the env is review lab and the review lab FF is enabled
    # Returns false otherwise
    def self.credential_revocation_oauth_app_tokens_enabled?
      return true if FeatureFlag.vexi.enabled?(:credential_revocation_oauth_app_tokens, default: false)
      return true if enabled_for_review_lab?
      false
    end

    # Public: Determines if U2S token revocation is enabled
    # Returns true if the credential_revocation_u2s_tokens FF is enabled,
    # or if the env is review lab and the review lab FF is enabled
    # Returns false otherwise
    def self.credential_revocation_u2s_tokens_enabled?
      return true if FeatureFlag.vexi.enabled?(:credential_revocation_u2s_tokens, default: false)
      return true if enabled_for_review_lab?
      false
    end

    # Public: Determines if S2S token revocation is enabled
    # Returns true if the credential_revocation_s2s_tokens FF is enabled,
    # or if the env is review lab and the review lab FF is enabled
    # Returns false otherwise
    def self.credential_revocation_s2s_tokens_enabled?
      return true if FeatureFlag.vexi.enabled?(:credential_revocation_s2s_tokens, default: false)
      return true if enabled_for_review_lab?
      false
    end

    # Public: Determines if refresh token revocation is enabled
    # Returns true if the credential_revocation_refresh_tokens FF is enabled,
    # or if the env is review lab and the review lab FF is enabled
    # Returns false otherwise
    def self.credential_revocation_refresh_tokens_enabled?
      return true if FeatureFlag.vexi.enabled?(:credential_revocation_refresh_tokens, default: false)
      return true if enabled_for_review_lab?
      false
    end

    def self.credential_revocation_keys_list
      GitHub.credential_revocation_keys.split(",")
    end

    def self.encrypt_credentials(credentials)
      return if credentials.empty?

      keys = self.credential_revocation_keys_list

      Kernel.raise RuntimeError.new("credential_revocation_keys not set") if keys.empty?

      # Ensure the encryption box is available
      decoded_key = Base64.strict_decode64(keys.last)
      box = RbNaCl::SimpleBox.from_secret_key(decoded_key)

      Kernel.raise RuntimeError.new("Encryption box not initialized") if box.nil?

      track_credential_revocation_key_usage(decoded_key, keys.length - 1)
      encrypted_credentials = box.encrypt(credentials.to_json)

      Base64.strict_encode64(encrypted_credentials)
    end

    def self.decrypt_credentials(credentials)
      return if credentials.blank?
      decoded_credentials = Base64.strict_decode64(credentials)

      keys = self.credential_revocation_keys_list
      Kernel.raise RuntimeError.new("credential_revocation_keys not set") if keys.empty?

      keys.each_with_index do |key, idx|
        begin
          decoded_key = Base64.strict_decode64(key)

          track_credential_revocation_key_usage(decoded_key, idx)
          box = RbNaCl::SimpleBox.from_secret_key(decoded_key)
          next if box.nil?

          string_creds = box.decrypt(decoded_credentials)
          return JSON.parse(string_creds).transform_keys(&:to_sym)
        rescue RbNaCl::CryptoError => error
          next if idx < keys.size - 1

          # None of the keys worked, report error
          Failbot.report(error)
        end
      end
    end

    private_class_method def self.enabled_for_review_lab?
      GitHub.review_lab? && FeatureFlag.vexi.enabled?(:credential_revocation_api_review_lab, default: false)
    end

    private_class_method def self.track_credential_revocation_key_usage(key, idx)
      # When rolling keys, we want to track usage of the old key
      # Once we see no usage of the old key, we know its safe to remove it
      # This is so we don't end up with a massive list of old keys
      key_id = Digest::SHA256.hexdigest(key)[0..7]
      GitHub.dogstats.increment("token_revocation.key_usage", tags: ["id:#{key_id}", "index:#{idx}"])
    end
  end
end
