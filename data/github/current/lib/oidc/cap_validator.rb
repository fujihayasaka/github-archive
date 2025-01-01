# typed: true
# frozen_string_literal: true
require "oidc"
require "digest/sha2"
module OIDC
  class CapValidator
    CACHE_KEY_PREFIX = "oidc_refresh_token_cache_"
    UNSATISFIED_ACTION = "external_cap.unsatisfied"
    SATISFIED_ACTION = "external_cap.satisfied"
    SATISFIED_CACHE_ACTION = "external_cap.satisfied_cache"
    UNSATISFIED_CACHE_ACTION = "external_cap.unsatisfied_cache"
    REFRESH_TOKEN = "refresh_token"
    ERROR_DESCRIPTION = "error_description"
    TRUE = "true"
    FALSE = "false"

    extend OIDCDependency

    def self.satisfies_idp_cap?(business:, refresh_token:, client_ip:, external_identity:)
      key = cache_key(external_identity, client_ip)

      if cache_enabled?(business) && GitHub.kv.get(key).value { nil } # rubocop:todo GitHub/DoNotUseGlobalKv
        GitHub.logger.info(
          "code.function" => SATISFIED_CACHE_ACTION,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.client_ip" => client_ip
        )

        :yes
      else
        res = refresh_token_access_token_request(business: business, refresh_token: refresh_token, client_ip: client_ip)

        # need to check res.body for tests, since they are stubbing a return
        body = if res.body.present?
          begin
            JSON.parse(res.body)
          rescue JSON::ParserError
            nil
          end
        end

        if res.success? && body
          refresh_token = body[REFRESH_TOKEN]

          ActiveRecord::Base.connected_to(role: :writing) do
            begin
              external_identity.set_refresh_token(refresh_token)
            rescue ActiveRecord::ValueTooLong => e
              GitHub.logger.error("Unable to set refresh token from AAD",
                {
                  "http.status_code" => res.status,
                  "gh.business.name" => business.slug,
                  "gh.external_identities.oid" => external_identity.external_id,
                  "gh.external_identities.refresh_token_size" => refresh_token&.bytesize,
                }
              )

              return :no
            end

            if cache_enabled?(business)
              begin
                GitHub.kv.set(key, TRUE, expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
              rescue GitHub::KV::UnavailableError
                # noop, if we can't set the cache we don't want to fail the request
              end
            end
          end

          GitHub.logger.info(
            "code.function" => SATISFIED_ACTION,
            "http.status_code" => res.status,
            "gh.business.name" => business.slug,
            "enduser.id" => external_identity.user.login,
            "gh.external_identities.oid" => external_identity.external_id,
            "gh.external_identities.client_ip" => client_ip
          )

          return :yes
        end

        message = body[ERROR_DESCRIPTION] if body && body[ERROR_DESCRIPTION]

        GitHub.logger.info(
          "code.function" => UNSATISFIED_ACTION,
          "http.status_code" => res.status,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.cap_message" => message,
          "gh.external_identities.token_url" => res.env.url.to_s,
        )

        message ? message : :no
      end
    end

    def self.satisfies_idp_web_cap?(business:, refresh_token:, client_ip:, external_identity:)
      key = cache_key(external_identity, client_ip)

      if cache_enabled?(business) && (value = GitHub.kv.get(key).value { nil }).present? # rubocop:todo GitHub/DoNotUseGlobalKv
        GitHub.logger.info(
          "code.function" => value == TRUE ? SATISFIED_CACHE_ACTION : UNSATISFIED_CACHE_ACTION,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.client_ip" => client_ip
        )

        value == TRUE ? :yes : :no
      else
        res = refresh_token_access_token_request(business: business, refresh_token: refresh_token, client_ip: client_ip)

        # need to check res.body for tests, since they are stubbing a return
        body = if res.body.present?
          begin
            JSON.parse(res.body)
          rescue JSON::ParserError
            nil
          end
        end

        if res.success? && body
          refresh_token = body[REFRESH_TOKEN]

          ActiveRecord::Base.connected_to(role: :writing) do
            begin
              external_identity.set_refresh_token(refresh_token)
            rescue ActiveRecord::ValueTooLong => e
              GitHub.logger.error("Unable to set refresh token from AAD",
                {
                  "http.status_code" => res.status,
                  "gh.business.name" => business.slug,
                  "gh.external_identities.oid" => external_identity.external_id,
                  "gh.external_identities.refresh_token_size" => refresh_token&.bytesize,
                }
              )

              return :no
            end

            if cache_enabled?(business)
              begin
                GitHub.kv.set(key, TRUE, expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
              rescue GitHub::KV::UnavailableError
                # noop, if we can't set the cache we don't want to fail the request
              end
            end
          end

          GitHub.logger.info(
            "code.function" => SATISFIED_ACTION,
            "http.status_code" => res.status,
            "gh.business.name" => business.slug,
            "enduser.id" => external_identity.user.login,
            "gh.external_identities.oid" => external_identity.external_id,
            "gh.external_identities.client_ip" => client_ip
          )

          return :yes
        end

        if cache_enabled?(business)
          ActiveRecord::Base.connected_to(role: :writing) do
            begin
              GitHub.kv.set(key, FALSE, expires: 1.hour.from_now) # rubocop:todo GitHub/DoNotUseGlobalKv
            rescue GitHub::KV::UnavailableError
              # noop, if we can't set the cache we don't want to fail the request
            end
          end
        end

        message = body[ERROR_DESCRIPTION] if body && body[ERROR_DESCRIPTION]

        GitHub.logger.info(
          "code.function" => UNSATISFIED_ACTION,
          "http.status_code" => res.status,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.cap_message" => message,
          "gh.external_identities.token_url" => res.env.url.to_s,
        )

        message ? message : :no
      end
    end

    def self.cache_key(external_identity, client_ip)
      Digest::SHA256.hexdigest(CACHE_KEY_PREFIX + "#{external_identity.id}_#{client_ip}")
    end

    def self.cache_enabled?(business)
      return false unless business.present?
      return false if business.staff_owned?
      !GitHub.flipper[:disable_oidc_cap_cache].enabled?(business)
    end
  end
end
