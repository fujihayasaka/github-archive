# typed: strict
# frozen_string_literal: true

module CopilotSessions
  class CopilotApiToken
    # Error raised when the Copilot SWE Agent integration is not available
    # This typically occurs on GHES where the integration is not registered
    class IntegrationUnavailableError < StandardError
      sig { void }
      def initialize
        super("Copilot SWE Agent integration is not available")
      end
    end

    # Mint a new token alongside refresh token (public API for CAPI)
    sig { params(user: User, entry_point: Symbol, user_session: T.nilable(UserSession)).returns(T::Hash[Symbol, T.untyped]) }
    def self.mint_with_refresh(user:, entry_point:, user_session:)
      GitHub.tracer.in_span("copilot_agent_session#mint_with_refresh", kind: :internal) do
        GitHub.dogstats.distribution_time("copilot_agent_session.mint_with_refresh.latency") do
          app = Apps::Privileged.integration(:copilot_swe_agent)
          raise IntegrationUnavailableError unless app

          new_access = app.grant(user, { user_session: user_session, entry_point: entry_point })
          access_token, refresh_token = new_access.redeem(extended_expiry: true)

          GitHub.dogstats.increment("copilot_api_token.mint", tags: ["result:new_grant"])
          GitHub.logger.info("copilot_agent_session token minted with refresh", log_context(user: user, entry_point: entry_point))

          {
            encrypted_token: encrypt_and_encode(access_token),
            expiration: new_access.expires_at,
            refresh_token: encrypt_and_encode(refresh_token)
          }
        end
      end
    end

    # Refresh existing token using refresh token (public API for CAPI)
    sig { params(user: User, refresh_token_value: String, entry_point: Symbol).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def self.refresh(user:, refresh_token_value:, entry_point:)
      GitHub.tracer.in_span("copilot_agent_session#refresh", kind: :internal) do
        GitHub.dogstats.distribution_time("copilot_agent_session.refresh.latency") do
          app = Apps::Privileged.integration(:copilot_swe_agent)
          raise IntegrationUnavailableError unless app

          decrypted_refresh_token = decrypt_refresh_token(refresh_token_value)
          unless decrypted_refresh_token
            GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:decrypt_failed"])
            return nil
          end

          lookup_result = RefreshToken.for_plaintext_token(decrypted_refresh_token, application: app)

          unless lookup_result.token
            GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:#{lookup_result.reason}"])
            return nil
          end

          refresh_token_record = lookup_result.token

          # Verify refresh token belongs to user
          access = refresh_token_record.refreshable
          unless access.is_a?(OauthAccess) && access.user_id == user.id
            GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:user_mismatch"])
            return nil
          end

          # Redeem the refresh token
          access_token, new_refresh_token = refresh_token_record.redeem(entry_point: entry_point)

          GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:success"])
          GitHub.logger.info("copilot_agent_session token refreshed", log_context(user: user, entry_point: entry_point))

          {
            encrypted_token: encrypt_and_encode(access_token),
            expiration: access.expires_at,
            refresh_token: encrypt_and_encode(new_refresh_token)
          }
        end
      end
    end

    # Get an encrypted token for the user, using session-cached refresh token if available.
    sig do
      params(
        user: User,
        entry_point: Symbol,
        user_session: T.nilable(UserSession),
        force_cache_miss: T::Boolean
      ).returns(Copilot::EncryptedToken)
    end
    def self.get_encrypted(user:, entry_point:, user_session:, force_cache_miss: false)
      feature_enabled = FeatureFlag.vexi.enabled?(:mission_control_refresh_existing_tokens, user, default: false)

      refresh_token_cache = CopilotAgentRefreshTokenCache.new(user)
      refresh_token_value = nil
      cached_tokens = nil
      sso_context_changed = false

      sso_org_ids = compute_sso_org_ids(user: user, user_session: user_session)

      if feature_enabled
        cached_tokens = refresh_token_cache.get_tokens
        refresh_token_value = cached_tokens&.dig(:refresh_token)

        # Check if SSO context has changed - if so, we need to refresh even if access token is valid
        if cached_tokens && !refresh_token_cache.sso_context_matches?(sso_org_ids)
          sso_context_changed = true
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:sso_context_changed"])
          GitHub.logger.info(
            "copilot_agent_session SSO context changed, forcing refresh",
            {
              "gh.user.id" => user.id,
              "gh.copilot_coding_agent.entry_point" => entry_point,
              "gh.copilot_coding_agent.cached_sso_org_ids" => cached_tokens[:sso_org_ids],
              "gh.copilot_coding_agent.current_sso_org_ids" => sso_org_ids,
              "gh.request_id" => GitHub.context[:request_id],
            }
          )
        end

        # Check if we have a valid access token in user cache (avoids regeneration)
        # Skip cache if SSO context changed - we need to refresh the token
        if !force_cache_miss && !sso_context_changed && cached_tokens && refresh_token_cache.access_token_valid?
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:access_token_hit"])
          GitHub.logger.info(
            "copilot_agent_session returning cached access token",
            {
              "gh.user.id" => user.id,
              "gh.copilot_coding_agent.entry_point" => entry_point,
              "gh.request_id" => GitHub.context[:request_id],
            }
          )
          return Copilot::EncryptedToken.from(
            cached_tokens[:access_token],
            expiration: cached_tokens[:expiration]
          )
        elsif force_cache_miss
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:forced_miss"])
        elsif refresh_token_value.present?
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:refresh_token_hit"])
        else
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:miss"])
        end
      end

      GitHub.logger.info(
        "copilot_agent_session get_encrypted called",
        {
          "gh.user.id" => user.id,
          "gh.copilot_coding_agent.feature_enabled" => feature_enabled,
          "gh.copilot_coding_agent.has_user_cached_refresh_token" => refresh_token_value.present?,
          "gh.copilot_coding_agent.sso_context_changed" => sso_context_changed,
          "gh.copilot_coding_agent.entry_point" => entry_point,
          "gh.request_id" => GitHub.context[:request_id],
        }
      )

      # Get token (with or without refresh token depending on feature flag)
      result = get_token(
        user: user,
        entry_point: entry_point,
        user_session: user_session,
        refresh_token_value: sso_context_changed ? nil : refresh_token_value,
        feature_enabled: feature_enabled
      )

      # Store both access token and refresh token in user cache to avoid regeneration on next prefetch
      if feature_enabled && result[:refresh_token]
        refresh_token_cache.set_tokens(
          access_token: result[:encrypted_token],
          expiration: result[:expiration],
          refresh_token: result[:refresh_token],
          sso_org_ids: sso_org_ids
        )
      end

      Copilot::EncryptedToken.from(
        result[:encrypted_token],
        expiration: result[:expiration]
      )
    end

    # Internal method to get or create a token
    sig do
      params(
        user: User,
        entry_point: Symbol,
        user_session: T.nilable(UserSession),
        refresh_token_value: T.nilable(String),
        feature_enabled: T::Boolean
      ).returns(T::Hash[Symbol, T.untyped])
    end
    private_class_method def self.get_token(user:, entry_point:, user_session:, refresh_token_value:, feature_enabled:)
      GitHub.tracer.in_span("copilot_agent_session#get_token", kind: :internal) do
        GitHub.dogstats.distribution_time("copilot_agent_session.get_token.latency") do
          app = Apps::Privileged.integration(:copilot_swe_agent)
          raise IntegrationUnavailableError unless app

          if feature_enabled && refresh_token_value.present?
            # Try to use provided refresh token first
            refresh_result = try_use_provided_refresh_token(
              user: user,
              app: app,
              refresh_token_value: refresh_token_value,
              entry_point: entry_point
            )
            if refresh_result
              GitHub.dogstats.increment("copilot_api_token.mint", tags: ["result:refreshed_provided"])
              return refresh_result
            end
          end

          # Mint a new token
          mint_new_token(user: user, app: app, user_session: user_session, entry_point: entry_point, include_refresh: feature_enabled)
        end
      end
    end

    # Try to use a provided refresh token
    sig { params(user: User, app: Integration, refresh_token_value: String, entry_point: Symbol).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    private_class_method def self.try_use_provided_refresh_token(user:, app:, refresh_token_value:, entry_point:)
      decrypted_refresh_token = decrypt_refresh_token(refresh_token_value)
      unless decrypted_refresh_token
        GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:decrypt_failed"])
        return nil
      end

      lookup_result = RefreshToken.for_plaintext_token(decrypted_refresh_token, application: app)

      unless lookup_result.token
        GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:#{lookup_result.reason}"])
        return nil
      end

      refresh_token_record = lookup_result.token

      # Verify refresh token belongs to user
      access = refresh_token_record.refreshable
      unless access.is_a?(OauthAccess) && access.user_id == user.id
        GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:user_mismatch"])
        return nil
      end

      # Set entry_point on the OauthAccess so it's available when reset_with_expiry
      # calls extend_expires_at on the installation (if present)
      access.entry_point = entry_point

      # Redeem the refresh token (must use primary database for writes)
      access_token, new_refresh_token = ActiveRecord::Base.connected_to(role: :writing) do
        refresh_token_record.redeem(entry_point: entry_point)
      end
      access.reload

      {
        encrypted_token: encrypt_and_encode(access_token),
        expiration: access.expires_at,
        refresh_token: encrypt_and_encode(new_refresh_token)
      }
    rescue StandardError
      # Log failure and return nil to trigger fallback to minting new token
      GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:error"])
      nil
    end

    # Mint a new token
    sig do
      params(
        user: User,
        app: Integration,
        user_session: T.nilable(UserSession),
        entry_point: Symbol,
        include_refresh: T::Boolean
      ).returns(T::Hash[Symbol, T.untyped])
    end
    private_class_method def self.mint_new_token(user:, app:, user_session:, entry_point:, include_refresh:)
      # Grant and redeem must use primary database for writes
      new_access, access_token, refresh_token = ActiveRecord::Base.connected_to(role: :writing) do
        access = app.grant(user, { user_session: user_session, entry_point: entry_point })
        token, refresh = access.redeem(extended_expiry: true)
        [access, token, refresh]
      end

      GitHub.dogstats.increment("copilot_api_token.mint", tags: ["result:new_grant"])

      {
        encrypted_token: encrypt_and_encode(access_token),
        expiration: new_access.expires_at,
        refresh_token: include_refresh ? encrypt_and_encode(refresh_token) : nil
      }
    end

    sig { params(token: String).returns(String) }
    private_class_method def self.encrypt_and_encode(token)
      encrypted = GitHub.dotcom_capi_simple_box.encrypt(token)
      Base64.urlsafe_encode64(encrypted)
    end

    sig { params(encrypted_token: String).returns(T.nilable(String)) }
    private_class_method def self.decrypt_refresh_token(encrypted_token)
      decoded = Base64.urlsafe_decode64(encrypted_token)
      GitHub.dotcom_capi_simple_box.decrypt(decoded)
    rescue StandardError
      nil
    end

    sig { params(user: User, entry_point: Symbol).returns(T::Hash[String, T.untyped]) }
    private_class_method def self.log_context(user:, entry_point:)
      {
        "gh.user.id" => user.id,
        "gh.copilot_coding_agent.entry_point" => entry_point,
        "gh.request_id" => GitHub.context[:request_id],
      }
    end

    # Compute SSO-protected org IDs for the user's session.
    sig { params(user: User, user_session: T.nilable(UserSession)).returns(T::Array[Integer]) }
    private_class_method def self.compute_sso_org_ids(user:, user_session:)
      saml = if user_session
        Platform::Authorization::SAML.new(session: user_session) # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
      else
        Platform::Authorization::SAML.new(user: user) # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
      end

      saml.protected_organization_ids
    end
  end
end
