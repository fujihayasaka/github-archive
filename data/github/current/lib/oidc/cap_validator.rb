# typed: true
# frozen_string_literal: true

require "oidc"
require "digest/sha2"
module OIDC
  class CapValidator
    # can be removed with :use_cap_validator_cache_class
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

    sig { params(business: T.nilable(Business), client_ip: T.nilable(String), external_identity: T.nilable(ExternalIdentity)).returns(T.any(Symbol, String)) }
    def self.satisfies_idp_cap?(business:, client_ip:, external_identity:)
      if business&.feature_enabled?(:use_cap_validator_cache_class)
        satisfies_idp_cap_new?(business: business, client_ip: client_ip, external_identity: external_identity)
      else
        satisfies_idp_cap_old?(business: business, client_ip: client_ip, external_identity: external_identity)
      end

    end

    sig { params(business: T.nilable(Business), client_ip: T.nilable(String), external_identity: T.nilable(ExternalIdentity)).returns(T.any(Symbol, String)) }
    def self.satisfies_idp_web_cap?(business:, client_ip:, external_identity:)
      if business&.feature_enabled?(:use_cap_validator_cache_class)
        satisfies_idp_web_cap_new?(business: business, client_ip: client_ip, external_identity: external_identity)
      else
        satisfies_idp_web_cap_old?(business: business, client_ip: client_ip, external_identity: external_identity)
      end
    end

    def self.log_dogstats(stat, business)
      GitHub.dogstats.increment("external_identities.#{stat}")
    end

    sig { params(business: Business, external_identity: ExternalIdentity, refresh_token: String, client_ip: String, cache_value: String).void }
    def self.instrument_refresh_token_event_and_cache_write(business, external_identity, refresh_token, client_ip, cache_value: TRUE)
      if business.feature_enabled?(:backgrounded_cache_write)
        GlobalInstrumenter.instrument("external_identity.refresh_token", {
          external_identity: external_identity,
          refresh_token: refresh_token,
          client_ip: client_ip,
          cache_value: cache_value,
        })
        CapValidatorCache.write(business, external_identity, client_ip, cache_value, ephemeral_only: true)
      else
        GlobalInstrumenter.instrument("external_identity.refresh_token", {
          external_identity: external_identity,
          refresh_token: refresh_token,
        })
        CapValidatorCache.write(business, external_identity, client_ip, cache_value)
      end
    end

    # can be removed with :use_cap_validator_cache_class
    def self.instrument_refresh_token_event_and_cache_write_old(res, business, external_identity, refresh_token, client_ip)
      GlobalInstrumenter.instrument("external_identity.refresh_token", {
        external_identity: external_identity,
        refresh_token: refresh_token,
      })

      key = cache_key(external_identity, client_ip)
      write_cache_record(business, key, TRUE)
    end

    # can be removed with :use_cap_validator_cache_class
    private_class_method def self.satisfies_idp_cap_old?(business:, client_ip:, external_identity:)
      key = cache_key(external_identity, client_ip)

      if cache_enabled?(business) && ExternalIdentities::KV.get(key).value { nil }
        GitHub.logger.info(
          "code.function" => SATISFIED_CACHE_ACTION,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.client_ip" => client_ip
        )
        log_dogstats(SATISFIED_CACHE_ACTION, business)

        :yes
      else
        existing_refresh_token = external_identity&.external_identity_refresh_token&.refresh_token
        return :no unless existing_refresh_token

        res = refresh_token_access_token_request(business: business, refresh_token: existing_refresh_token, client_ip: client_ip)

        # need to check res.body for tests, since they are stubbing a return
        body = if res.body.present?
          begin
            JSON.parse(res.body)
          rescue JSON::ParserError
            nil
          end
        end

        if res.success? && body
          new_refresh_token = body[REFRESH_TOKEN]
          ret_val = instrument_refresh_token_event_and_cache_write_old(res, business, external_identity, new_refresh_token, client_ip)
          return ret_val if ret_val == :no

          GitHub.logger.info(
            "code.function" => SATISFIED_ACTION,
            "http.status_code" => res.status,
            "gh.business.name" => business.slug,
            "enduser.id" => external_identity.user.login,
            "gh.external_identities.oid" => external_identity.external_id,
            "gh.external_identities.client_ip" => client_ip
          )
          log_dogstats(SATISFIED_ACTION, business)

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
        log_dogstats(UNSATISFIED_ACTION, business)

        message ? message : :no
      end
    end

    sig { params(business: T.nilable(Business), client_ip: T.nilable(String), external_identity: T.nilable(ExternalIdentity)).returns(T.any(Symbol, String)) }
    private_class_method def self.satisfies_idp_cap_new?(business:, client_ip:, external_identity:)
      unless business && client_ip && external_identity
        is_missing_business = !business.present?
        is_missing_client_ip = !client_ip.present?
        is_missing_external_identity = !external_identity.present?
        GitHub.dogstats.increment("cap_validator.satisfied.missing_params", tags: ["is_missing_business:#{is_missing_business}", "is_missing_client_ip:#{is_missing_client_ip}", "is_missing_external_identity:#{is_missing_external_identity}"])
        return :no
      end

      if cache_response = CapValidatorCache.get(business, external_identity, client_ip)
        value, value_from = cache_response
        GitHub.logger.info(
          "code.function" => SATISFIED_CACHE_ACTION,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user&.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.client_ip" => client_ip,
          "gh.external_identities.cached_response.from" => value_from,
        )
        log_dogstats(SATISFIED_CACHE_ACTION, business)

        :yes
      else
        existing_refresh_token = external_identity.external_identity_refresh_token&.refresh_token
        return :no unless existing_refresh_token

        res = refresh_token_access_token_request(business: business, refresh_token: existing_refresh_token, client_ip: client_ip)

        # need to check res.body for tests, since they are stubbing a return
        body = if res.body.present?
          begin
            JSON.parse(res.body)
          rescue JSON::ParserError
            nil
          end
        end

        if res.success? && body
          new_refresh_token = body[REFRESH_TOKEN]
          instrument_refresh_token_event_and_cache_write(business, external_identity, new_refresh_token, client_ip, cache_value: TRUE)

          GitHub.logger.info(
            "code.function" => SATISFIED_ACTION,
            "http.status_code" => res.status,
            "gh.business.name" => business.slug,
            "enduser.id" => external_identity.user&.login,
            "gh.external_identities.oid" => external_identity.external_id,
            "gh.external_identities.client_ip" => client_ip
          )
          log_dogstats(SATISFIED_ACTION, business)

          return :yes
        end

        message = body[ERROR_DESCRIPTION] if body && body[ERROR_DESCRIPTION]

        GitHub.logger.info(
          "code.function" => UNSATISFIED_ACTION,
          "http.status_code" => res.status,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user&.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.cap_message" => message,
          "gh.external_identities.token_url" => res.env.url.to_s,
        )
        log_dogstats(UNSATISFIED_ACTION, business)

        message ? message : :no
      end
    end

    # can be removed with :use_cap_validator_cache_class
    private_class_method def self.satisfies_idp_web_cap_old?(business:, client_ip:, external_identity:)
      key = cache_key(external_identity, client_ip)

      if cache_enabled?(business) && (value = ExternalIdentities::KV.get(key).value { nil }).present?
        code_function = if value == TRUE
          SATISFIED_CACHE_ACTION
        else
          UNSATISFIED_CACHE_ACTION
        end
        GitHub.logger.info(
          "code.function" => code_function,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.client_ip" => client_ip
        )
        log_dogstats(code_function, business)

        value == TRUE ? :yes : :no
      else
        existing_refresh_token = external_identity&.async_external_identity_refresh_token&.sync&.refresh_token
        return :no unless existing_refresh_token

        res = refresh_token_access_token_request(business: business, refresh_token: existing_refresh_token, client_ip: client_ip)

        # need to check res.body for tests, since they are stubbing a return
        body = if res.body.present?
          begin
            JSON.parse(res.body)
          rescue JSON::ParserError
            nil
          end
        end

        if res.success? && body
          new_refresh_token = body[REFRESH_TOKEN]
          ret_val = instrument_refresh_token_event_and_cache_write_old(res, business, external_identity, new_refresh_token, client_ip)
          return ret_val if ret_val == :no

          GitHub.logger.info(
            "code.function" => SATISFIED_ACTION,
            "http.status_code" => res.status,
            "gh.business.name" => business.slug,
            "enduser.id" => external_identity.user.login,
            "gh.external_identities.oid" => external_identity.external_id,
            "gh.external_identities.client_ip" => client_ip
          )
          log_dogstats(SATISFIED_ACTION, business)

          return :yes
        end

        write_cache_record(business, key, FALSE)

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
        log_dogstats(UNSATISFIED_ACTION, business)

        message ? message : :no
      end
    end

    sig { params(business: T.nilable(Business), client_ip: T.nilable(String), external_identity: T.nilable(ExternalIdentity)).returns(T.any(Symbol, String)) }
    def self.satisfies_idp_web_cap_new?(business:, client_ip:, external_identity:)
      unless business && client_ip && external_identity
        is_missing_business = !business.present?
        is_missing_client_ip = !client_ip.present?
        is_missing_external_identity = !external_identity.present?
        GitHub.dogstats.increment("cap_validator.satisfied.missing_params", tags: ["is_missing_business:#{is_missing_business}", "is_missing_client_ip:#{is_missing_client_ip}", "is_missing_external_identity:#{is_missing_external_identity}"])
        return :no
      end

      if (cache_response = CapValidatorCache.get(business, external_identity, client_ip)).present?
        value, value_from = cache_response
        code_function = if value == TRUE
          SATISFIED_CACHE_ACTION
        else
          UNSATISFIED_CACHE_ACTION
        end
        GitHub.logger.info(
          "code.function" => code_function,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user&.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.client_ip" => client_ip,
          "gh.external_identities.cached_response.from" => value_from,
        )
        log_dogstats(code_function, business)

        value == TRUE ? :yes : :no
      else
        existing_refresh_token = external_identity.async_external_identity_refresh_token.sync&.refresh_token
        return :no unless existing_refresh_token

        res = refresh_token_access_token_request(business: business, refresh_token: existing_refresh_token, client_ip: client_ip)

        # need to check res.body for tests, since they are stubbing a return
        body = if res.body.present?
          begin
            JSON.parse(res.body)
          rescue JSON::ParserError
            nil
          end
        end

        if res.success? && body
          new_refresh_token = body[REFRESH_TOKEN]
          instrument_refresh_token_event_and_cache_write(business, external_identity, new_refresh_token, client_ip, cache_value: TRUE)

          GitHub.logger.info(
            "code.function" => SATISFIED_ACTION,
            "http.status_code" => res.status,
            "gh.business.name" => business.slug,
            "enduser.id" => external_identity.user&.login,
            "gh.external_identities.oid" => external_identity.external_id,
            "gh.external_identities.client_ip" => client_ip
          )
          log_dogstats(SATISFIED_ACTION, business)

          return :yes
        end

        instrument_refresh_token_event_and_cache_write(business, external_identity, existing_refresh_token, client_ip, cache_value: FALSE)

        message = body[ERROR_DESCRIPTION] if body && body[ERROR_DESCRIPTION]
        GitHub.logger.info(
          "code.function" => UNSATISFIED_ACTION,
          "http.status_code" => res.status,
          "gh.business.name" => business.slug,
          "enduser.id" => external_identity.user&.login,
          "gh.external_identities.oid" => external_identity.external_id,
          "gh.external_identities.cap_message" => message,
          "gh.external_identities.token_url" => res.env.url.to_s,
        )
        log_dogstats(UNSATISFIED_ACTION, business)

        message ? message : :no
      end
    end

    # can be removed with :use_cap_validator_cache_class
    def self.cache_key(external_identity, client_ip)
      Digest::SHA256.hexdigest(CACHE_KEY_PREFIX + "#{external_identity.id}_#{client_ip}")
    end

    # can be removed with :use_cap_validator_cache_class
    private_class_method def self.cache_enabled?(business)
      return false unless business.present?
      return false if business.staff_owned?
      !GitHub.flipper[:disable_oidc_cap_cache].enabled?(business)
    end

    # can be removed with :use_cap_validator_cache_class
    private_class_method def self.write_cache_record(business, key, value)
      if cache_enabled?(business)
        ActiveRecord::Base.connected_to(role: :writing) do
          begin
            ExternalIdentities::KV.set(key, value, expires: 1.hour.from_now)
          rescue GitHub::KV::UnavailableError
            # noop, if we can't set the cache we don't want to fail the request
            GitHub.logger.error("KV cache is unavailable",
              {
                "gh.business.name" => business.slug,
                "gh.external_identities.kv.key" => key,
                "gh.external_identities.kv.value" => value,
              }
            )
          end
        end
      end
    end
  end
end
