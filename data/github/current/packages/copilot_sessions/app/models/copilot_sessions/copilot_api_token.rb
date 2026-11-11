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
      sso_org_ids = compute_sso_org_ids(user: user, user_session: user_session)
      bucket_tag = sso_org_ids_bucket_tag(sso_org_ids)
      GitHub.tracer.in_span("copilot_agent_session#mint_with_refresh", kind: :internal) do
        GitHub.dogstats.distribution_time("copilot_agent_session.mint_with_refresh.latency", tags: [bucket_tag]) do
          app = Apps::Privileged.integration(:copilot_swe_agent)
          raise IntegrationUnavailableError unless app

          new_access = app.grant(user, { user_session: user_session, entry_point: entry_point })
          ensure_saml_credential_authorizations(user: user, access: new_access, user_session: user_session, sso_org_ids: sso_org_ids)
          access_token, refresh_token = new_access.redeem(extended_expiry: true)

          GitHub.dogstats.increment("copilot_api_token.mint", tags: ["result:new_grant", bucket_tag])
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
      sso_org_ids = compute_sso_org_ids(user: user, user_session: nil)
      bucket_tag = sso_org_ids_bucket_tag(sso_org_ids)
      GitHub.tracer.in_span("copilot_agent_session#refresh", kind: :internal) do
        GitHub.dogstats.distribution_time("copilot_agent_session.refresh.latency", tags: [bucket_tag]) do
          app = Apps::Privileged.integration(:copilot_swe_agent)
          raise IntegrationUnavailableError unless app

          decrypted_refresh_token = decrypt_refresh_token(refresh_token_value)
          unless decrypted_refresh_token
            GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:decrypt_failed", bucket_tag])
            return nil
          end

          lookup_result = RefreshToken.for_plaintext_token(decrypted_refresh_token, application: app)

          unless lookup_result.token
            GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:#{lookup_result.reason}", bucket_tag])
            return nil
          end

          refresh_token_record = lookup_result.token

          # Verify refresh token belongs to user
          access = refresh_token_record.refreshable
          unless access.is_a?(OauthAccess) && access.user_id == user.id
            GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:user_mismatch", bucket_tag])
            return nil
          end

          # Ensure SAML credential authorizations before redeeming so the
          # refresh token is not consumed if authorization setup fails.
          ensure_saml_credential_authorizations(user: user, access: access, sso_org_ids: sso_org_ids)

          # Redeem the refresh token
          access_token, new_refresh_token = refresh_token_record.redeem(entry_point: entry_point)

          GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:success", bucket_tag])
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
        force_cache_miss: T::Boolean,
      ).returns(Copilot::EncryptedToken)
    end
    def self.get_encrypted(user:, entry_point:, user_session:, force_cache_miss: false)
      get_encrypted_internal(
        user: user,
        entry_point: entry_point,
        user_session: user_session,
        force_cache_miss: force_cache_miss,
        background_actor: false,
      )
    end

    # Mint a CAPI token for a User from a background-job context where no
    # UserSession is available (e.g. a workflow action handler running in
    # Aqueduct on behalf of the user who configured it).
    #
    # Unlike `get_encrypted`, this path authorizes the minted token against
    # the user's current SAML-enforced organization memberships rather than
    # the orgs authenticated by a live session. Callers MUST be acting on
    # behalf of a human User whose intent to perform this action has been
    # captured upstream (e.g. ADR Decision 6 — Human-Only Triggers in the
    # Memex Autopilot ADR).
    #
    # Use this only when you cannot pass a UserSession through. Prefer
    # `get_encrypted` whenever a session is in scope.
    sig do
      params(
        user: User,
        entry_point: Symbol,
        force_cache_miss: T::Boolean,
      ).returns(Copilot::EncryptedToken)
    end
    def self.get_encrypted_for_background_actor(user:, entry_point:, force_cache_miss: false)
      get_encrypted_internal(
        user: user,
        entry_point: entry_point,
        user_session: nil,
        force_cache_miss: force_cache_miss,
        background_actor: true,
      )
    end

    sig do
      params(
        user: User,
        entry_point: Symbol,
        user_session: T.nilable(UserSession),
        force_cache_miss: T::Boolean,
        background_actor: T::Boolean,
      ).returns(Copilot::EncryptedToken)
    end
    private_class_method def self.get_encrypted_internal(user:, entry_point:, user_session:, force_cache_miss:, background_actor:)
      refresh_token_cache = CopilotAgentRefreshTokenCache.new(user)
      refresh_token_value = nil
      cached_tokens = nil
      sso_context_changed = false

      # Skip cache for PAT/API requests (no user_session) to avoid polluting the
      # session cache with PAT-derived SSO context that differs from the browser session.
      skip_cache = user_session.nil?

      sso_org_ids = compute_sso_org_ids(user: user, user_session: user_session, background_actor: background_actor)
      bucket_tag = sso_org_ids_bucket_tag(sso_org_ids)

      if !skip_cache
        cached_tokens = refresh_token_cache.get_tokens
        refresh_token_value = cached_tokens&.dig(:refresh_token)

        # Check if SSO context has changed - if so, we need to refresh even if access token is valid
        if cached_tokens && !refresh_token_cache.sso_context_matches?(sso_org_ids)
          sso_context_changed = true
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:sso_context_changed", bucket_tag])
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
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:access_token_hit", bucket_tag])
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
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:forced_miss", bucket_tag])
        elsif refresh_token_value.present?
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:refresh_token_hit", bucket_tag])
        else
          GitHub.dogstats.increment("copilot_api_token.session_cache", tags: ["result:miss", bucket_tag])
        end
      end

      GitHub.logger.info(
        "copilot_agent_session get_encrypted called",
        {
          "gh.user.id" => user.id,
          "gh.copilot_coding_agent.has_user_cached_refresh_token" => refresh_token_value.present?,
          "gh.copilot_coding_agent.sso_context_changed" => sso_context_changed,
          "gh.copilot_coding_agent.entry_point" => entry_point,
          "gh.request_id" => GitHub.context[:request_id],
        }
      )

      # Get a token result by reusing a cached access token when available,
      # otherwise refreshing with the cached refresh token, or minting a new token pair.
      result = get_token(
        user: user,
        entry_point: entry_point,
        user_session: user_session,
        refresh_token_value: sso_context_changed ? nil : refresh_token_value,
        sso_org_ids: sso_org_ids
      )

      # Store both access token and refresh token in user cache to avoid regeneration on next prefetch.
      # Skip cache writes for PAT/API requests to prevent SSO context pollution.
      if result[:refresh_token] && !skip_cache
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
        sso_org_ids: T.nilable(T::Array[Integer])
      ).returns(T::Hash[Symbol, T.untyped])
    end
    private_class_method def self.get_token(user:, entry_point:, user_session:, refresh_token_value:, sso_org_ids: nil)
      bucket_tag = sso_org_ids_bucket_tag(sso_org_ids)
      GitHub.tracer.in_span("copilot_agent_session#get_token", kind: :internal) do
        GitHub.dogstats.distribution_time("copilot_agent_session.get_token.latency", tags: [bucket_tag]) do
          app = Apps::Privileged.integration(:copilot_swe_agent)
          raise IntegrationUnavailableError unless app

          if refresh_token_value.present?
            # Try to use provided refresh token first
            refresh_result = try_use_provided_refresh_token(
              user: user,
              app: app,
              refresh_token_value: refresh_token_value,
              entry_point: entry_point,
              sso_org_ids: sso_org_ids
            )
            if refresh_result
              GitHub.dogstats.increment("copilot_api_token.mint", tags: ["result:refreshed_provided", bucket_tag])
              return refresh_result
            end
          end

          # Mint a new token
          mint_new_token(user: user, app: app, user_session: user_session, entry_point: entry_point, include_refresh: true, sso_org_ids: sso_org_ids)
        end
      end
    end

    # Try to use a provided refresh token
    sig { params(user: User, app: Integration, refresh_token_value: String, entry_point: Symbol, sso_org_ids: T.nilable(T::Array[Integer])).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    private_class_method def self.try_use_provided_refresh_token(user:, app:, refresh_token_value:, entry_point:, sso_org_ids: nil)
      bucket_tag = sso_org_ids_bucket_tag(sso_org_ids)
      decrypted_refresh_token = decrypt_refresh_token(refresh_token_value)
      unless decrypted_refresh_token
        GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:decrypt_failed", bucket_tag])
        return nil
      end

      lookup_result = RefreshToken.for_plaintext_token(decrypted_refresh_token, application: app)

      unless lookup_result.token
        GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:#{lookup_result.reason}", bucket_tag])
        return nil
      end

      refresh_token_record = lookup_result.token

      # Verify refresh token belongs to user
      access = refresh_token_record.refreshable
      unless access.is_a?(OauthAccess) && access.user_id == user.id
        GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:user_mismatch", bucket_tag])
        return nil
      end

      # Set entry_point on the OauthAccess so it's available when reset_with_expiry
      # calls extend_expires_at on the installation (if present)
      access.entry_point = entry_point

      # Ensure SAML credential authorizations before redeeming so the
      # refresh token is not consumed if authorization setup fails.
      unless FeatureFlag.vexi.enabled?(:skip_ensure_saml_for_refresh_tokens, user, default: false)
        ensure_saml_credential_authorizations(user: user, access: access, sso_org_ids: sso_org_ids)
      end

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
      GitHub.dogstats.increment("copilot_api_token.refresh", tags: ["result:error", bucket_tag])
      nil
    end

    # Mint a new token
    sig do
      params(
        user: User,
        app: Integration,
        user_session: T.nilable(UserSession),
        entry_point: Symbol,
        include_refresh: T::Boolean,
        sso_org_ids: T.nilable(T::Array[Integer])
      ).returns(T::Hash[Symbol, T.untyped])
    end
    private_class_method def self.mint_new_token(user:, app:, user_session:, entry_point:, include_refresh:, sso_org_ids: nil)
      bucket_tag = sso_org_ids_bucket_tag(sso_org_ids)

      # Grant access to get the app (must use primary database for writes)
      new_access = ActiveRecord::Base.connected_to(role: :writing) do
        access = app.grant(user, { user_session: user_session, entry_point: entry_point })
      end

      # Ensure SAML credential authorizations before redeeming so the
      # token is not generated if authorization setup fails.
      ensure_saml_credential_authorizations(user: user, access: new_access, user_session: user_session, sso_org_ids: sso_org_ids)

      access_token, refresh_token = new_access.redeem(extended_expiry: true)

      GitHub.dogstats.increment("copilot_api_token.mint", tags: ["result:new_grant", bucket_tag])

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

    # Compute SSO org IDs for the user's session.
    # Uses authorized_organization_ids which includes all SAML orgs the user has
    # authorized credentials for, regardless of whether the credential is the current
    # session or a PAT. This avoids the issue where protected_organization_ids returns
    # empty for PAT users who are already SSO-authorized (saml_orgs - authorized_orgs = []).
    sig { params(user: User, user_session: T.nilable(UserSession), background_actor: T::Boolean).returns(T::Array[Integer]) }
    private_class_method def self.compute_sso_org_ids(user:, user_session:, background_actor: false)
      saml = if user_session
        Platform::Authorization::SAML.new(session: user_session) # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
      else
        Platform::Authorization::SAML.new(user: user) # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
      end

      sso_org_ids = if !background_actor && FeatureFlag.vexi.enabled?(:copilot_agent_token_cache_v4, user, default: false)
        saml.authorized_organization_ids
      else
        saml.protected_organization_ids
      end

      if FeatureFlag.vexi.enabled?(:copilot_assignment_diagnostic_logging, default: false)
        auth_type = if user.programmatic_access.present?
          "fine_grained_pat"
        elsif user.oauth_access.present?
          "oauth"
        else
          "session"
        end
        GitHub.logger.info("copilot_sso_org_ids_diagnostic",
          "gh.user.id": user.id,
          "gh.is_emu": user.is_enterprise_managed?,
          "gh.has_session": user_session.present?,
          "gh.auth_type": auth_type,
          "gh.sso_org_ids_count": sso_org_ids.length,
          "gh.sso_org_ids": sso_org_ids,
          "gh.direct_org_ids_count": user.organization_ids.length,
          "gh.request_id": GitHub.context[:request_id],
        )
      end

      sso_org_ids
    end

    # Returns a Datadog tag bucketing the SSO org IDs count for observability.
    sig { params(sso_org_ids: T.nilable(T::Array[Integer])).returns(String) }
    private_class_method def self.sso_org_ids_bucket_tag(sso_org_ids)
      count = sso_org_ids&.size || 0
      bucket = case count
      when 0..5 then "0-5"
      when 6..10 then "6-10"
      when 11..20 then "11-20"
      when 21..50 then "21-50"
      when 51..100 then "51-100"
      when 101..200 then "101-200"
      else "200+"
      end
      "sso_org_ids_bucket:#{bucket}"
    end

    # Ensure SAML credential authorizations exist for the user's SAML-protected orgs.
    # Without this, tokens fail access checks in SAML-enforced orgs (404s).
    sig { params(user: User, access: OauthAccess, user_session: T.nilable(UserSession), sso_org_ids: T.nilable(T::Array[Integer])).void }
    private_class_method def self.ensure_saml_credential_authorizations(user:, access:, user_session: nil, sso_org_ids: nil)
      return unless FeatureFlag.vexi.enabled?(:mission_control_fix_saml_auth, user, default: false)

      sso_org_ids = compute_sso_org_ids(user: user, user_session: user_session) if sso_org_ids.nil?
      return if sso_org_ids.empty?

      orgs = Organization.where(id: sso_org_ids).to_a
      return if orgs.empty?

      enforced_orgs = Organization::SamlEnforcementPolicy.filter_enforced(orgs, user)
      return if enforced_orgs.empty?

      already_authorized_org_ids = Organization::CredentialAuthorization
        .by_organization(organization: enforced_orgs)
        .by_credential(credential: access)
        .active
        .pluck(:organization_id)
        .to_set

      orgs_needing_auth = enforced_orgs.reject { |org| already_authorized_org_ids.include?(org.id) }

      if FeatureFlag.vexi.enabled?(:copilot_assignment_diagnostic_logging, default: false)
        GitHub.logger.info("copilot_saml_credential_auth_diagnostic",
          "gh.user.id": user.id,
          "gh.is_emu": user.is_enterprise_managed?,
          "gh.sso_org_ids_count": sso_org_ids.length,
          "gh.enforced_orgs_count": enforced_orgs.length,
          "gh.already_authorized_count": already_authorized_org_ids.length,
          "gh.orgs_needing_auth_count": orgs_needing_auth.length,
          "gh.orgs_needing_auth_ids": orgs_needing_auth.map(&:id),
          "gh.request_id": GitHub.context[:request_id],
        )
      end

      return if orgs_needing_auth.empty?

      Organization::CredentialAuthorization.grant_in_bulk(
        organizations: orgs_needing_auth,
        credential: access,
        actor: user,
      )
    rescue StandardError => e
      GitHub.dogstats.increment("copilot_api_token.saml_credential_auth", tags: ["result:error", sso_org_ids_bucket_tag(sso_org_ids)])
      GitHub.logger.error(
        "copilot_agent_session ensure_saml_credential_authorizations failed",
        {
          "gh.user.id" => user.id,
          "gh.oauth_access.id" => access.id,
          "gh.error.class" => e.class.name,
          "gh.error.message" => e.message,
          "gh.request_id" => GitHub.context[:request_id],
        }
      )
    end
  end
end
