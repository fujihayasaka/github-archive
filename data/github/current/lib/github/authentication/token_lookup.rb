# typed: true
# frozen_string_literal: true

require "scientist"

module GitHub
  module Authentication
    # Encapsulates the process of looking up an access token and identifying its
    # corresponding actor (i.e., User or Bot).
    class TokenLookup
      class ActorNotFoundError < StandardError; end

      attr_reader :token, :ip, :user_agent

      USER_AGENTS = %w[zeit/now zeit/now/registration]
      FALLBACK_DELAY_TIMEOUT = 30

      # Public: Initialize a TokenLookup.
      #
      # token   - A String access token value.
      # request - The request that originated this token lookup.
      def initialize(token, ip: nil, user_agent: nil)
        @token = token
        @ip = ip || ""
        @user_agent = user_agent || ""
      end

      # Public: Return the actor (if any) associated with the token.
      def actor
        last_operations = DatabaseSelector::LastOperations.from_token(token)
        gtid_result_hash = {}
        DatabaseSelector.instance.read_from_database(
          last_operations: last_operations,
          called_from: :token_lookup,
          gtid_result_hash: gtid_result_hash,
        ) do
          begin
            actor = find_actor(gtid_result_hash)
            # track quantity of nil calls
            has_mysql1_latency = gtid_result_hash.has_key?(:mysql1) && gtid_result_hash[:mysql1][:gtid_lag] < FALLBACK_DELAY_TIMEOUT
            tags = {
              "result_found": !actor.nil?,
              "low_latency_cache": has_low_latency_cache?(gtid_result_hash),
              "has_mysql1": has_mysql1_latency,
              "replicas_ready": User.connected_to?(role: :reading),
              "token_type": token_type,
              "token_fallback": gtid_result_hash[:token_fallback]
            }

            tags_as_array = tags.map { |k, v| "#{k}:#{v}" }
            GitHub.dogstats.increment("token_lookup.result", tags: tags_as_array)

            if actor.nil? && token_type == :authentication_token && GitHub.flipper[:verbose_authentication_failures_logging].enabled?
              failure_details = tags
                .transform_keys { |k| "gh.verbose_authentication_failure.#{k}" }
                .merge(
                  "gh.catalog_service" => "github/apps",
                  "gh.verbose_authentication_failure.log_point" => "token_lookup",
                  "gh.verbose_authentication_failure.last_eight" => token.last(8),
                  "gh.verbose_authentication_failure.ip" => ip,
                  "gh.verbose_authentication_failure.user_agent" => user_agent,
                )

              GitHub.logger.info("Verbose authentication failure details", failure_details)
            end

            actor
          rescue ActiveRecord::RecordInvalid, RuntimeError, NoMethodError => e
            instrument_error(e)
            raise
          end
        end
      end

      # Check cache hash if cache value is present gtid_result_hash format is {:mysql{gtid_lag:}}
      def fallback_to_primary?(gtid_result_hash)
        ActiveRecord::Base.connected_to?(role: :reading) && has_low_latency_cache?(gtid_result_hash)
      end

      def has_low_latency_cache?(gtid_result_hash)
        !gtid_result_hash.empty? && gtid_result_hash.any? { |_, v| v.is_a?(Hash) && v.has_key?(:gtid_lag) && v[:gtid_lag] < FALLBACK_DELAY_TIMEOUT } # check for low latency caching
      end

      def mysql1_lag(gtid_result_hash)
        return gtid_result_hash[:mysql1][:gtid_lag] if !gtid_result_hash.nil? && gtid_result_hash.has_key?(:mysql1)
        FALLBACK_DELAY_TIMEOUT
      end

      private

      def find_actor(gtid_result_hash)
        gtid_result_hash[:token_fallback] = false
        case token_type
        when :oauth_access
          user = T.let(User.with_oauth_token(token), T.nilable(User))
          if user.nil? && GitHub.flipper[:token_lookup_from_primary_user].enabled? && fallback_to_primary?(gtid_result_hash)
            user = ActiveRecord::Base.connected_to(role: :writing) do
              ApplicationRecord::Domain::Users.uncached do
                gtid_result_hash[:token_fallback] = true
                user = User.with_oauth_token(token)
              end
            end
            GitHub.dogstats.distribution("token_lookup.fallback_to_primary.distribution", mysql1_lag(gtid_result_hash), tags: ["found_on_primary:#{!user.nil?}", "token_type:user"])
          end
          user
        when :authentication_token
          reduce_authentication_token_lookups = GitHub.flipper[:reduce_authentication_token_lookups].enabled?

          unless reduce_authentication_token_lookups
            # This Audit context addition catches integration token uses which are different from logged_in sessions
            hashed_token = ServerToServerTokens::Domain.hash_token(token)
            record = ServerToServerTokens.domain.by_hashed_token(hashed_token)
            Audit.context.push(token_id: record&.id) if hashed_token.present?
          end

          bot = Bot.find_by_token(token, push_token_to_audit_log: reduce_authentication_token_lookups)

          if bot.nil? && GitHub.flipper[:token_lookup_from_primary_bot].enabled? && ActiveRecord::Base.connected_to?(role: :reading)
            bot = ActiveRecord::Base.connected_to(role: :writing) do
              ApplicationRecord::Domain::Users.uncached do
                gtid_result_hash[:token_fallback] = true
                Bot.find_by_token(token)
              end
            end
            GitHub.dogstats.distribution("token_lookup.fallback_to_primary.distribution",  mysql1_lag(gtid_result_hash), tags: ["found_on_primary:#{!bot.nil?}", "token_type:bot"])
          end
          bot
        end
      end

      # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
      def token_type
        @token_type ||=
          case token
          when OauthAccessTokens::Domain.token_regex, OauthAccessTokens::Domain::TOKEN_LEGACY_PATTERN
            :oauth_access
          when ServerToServerTokens::Domain::TOKEN_PATTERN_GS1, ServerToServerTokens::Domain::TOKEN_PATTERN_V1
            :authentication_token
          end
      end
      # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

      # given that this is a high traffic flow, we prefer not to log the
      # successes as we can rely on the stats from
      # GitHub::Authentication::Attempt#instrument
      def instrument_error(e)
        GitHub.dogstats.increment("token_lookup.find_actor", tags: [
          "token_type:#{token_type}",
          "result:failure",
          "error:#{e.class.name.demodulize.underscore}"
        ])
      end
    end
  end
end
