# typed: strict
# frozen_string_literal: true

module CopilotSweAgent
  class CopilotApiToken
    sig { params(user: User, entry_point: Symbol, user_session: T.nilable(UserSession), force_cache_miss: T::Boolean).returns(Copilot::EncryptedToken) }
    def self.get_encrypted(user:, entry_point:, user_session:, force_cache_miss: false)
      cache_enabled = !GitHub.multi_tenant_enterprise? && !force_cache_miss
      token_cache_key = "copilot_coding_agent:capi_token:#{user.id}"
      token_cache_expiration_key = "copilot_coding_agent:capi_token_expiration:#{user.id}"
      if cache_enabled
        cached_token = GitHub.cache.get(token_cache_key)
        cached_expiration = GitHub.cache.get(token_cache_expiration_key)

        if cached_token && cached_expiration && Time.now < cached_expiration
          return Copilot::EncryptedToken.from(cached_token, expiration: cached_expiration)
        end
      end
      token, expires_at = get(user:, entry_point:, user_session:)
      encrypted = GitHub.dotcom_capi_simple_box.encrypt(token.to_s)
      encoded = Base64.urlsafe_encode64(encrypted)
      if cache_enabled
        GitHub.cache.set(token_cache_key, encoded, 1.minute)
        GitHub.cache.set(token_cache_expiration_key, expires_at, 1.minute)
      end
      Copilot::EncryptedToken.from(encoded, expiration: expires_at)
    end

    sig { params(user: User, entry_point: Symbol, user_session: T.nilable(UserSession)).returns([Copilot::DecryptedToken, Time]) }
    private_class_method def self.get(user:, entry_point:, user_session:)
      GitHub.tracer.in_span("copilot_agent_session#get", kind: :internal) do
        GitHub.dogstats.distribution_time("copilot_agent_session.get.latency") do
          app = Apps::Privileged.integration(:copilot_swe_agent)
          new_access = app.grant(user, { user_session: user_session, entry_point: entry_point })
          token, _ = new_access.redeem(extended_expiry: true)
          GitHub.logger.info(
            "copilot_agent_session token minted",
            {
              "gh.user.id" => user.id,
              "gh.catalog_service" => "github/copilot-coding-agent",
              "gh.copilot_coding_agent.get.entry_point" => entry_point,
              "gh.request_id" => GitHub.context[:request_id],
            }
          )
          [Copilot::DecryptedToken.from(token), new_access.expires_at]
        end
      end
    end
  end
end
