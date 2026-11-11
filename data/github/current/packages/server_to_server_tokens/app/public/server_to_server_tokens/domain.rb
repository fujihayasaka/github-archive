# typed: strict
# frozen_string_literal: true

module ServerToServerTokens
  class Domain < GH::Domain::Base
    include RedisWithMysqlFallback

    class CreateResult
      sig { returns(IAuthenticationToken) }
      attr_reader :token_record

      sig { returns(String) }
      attr_reader :token_value

      # initialize the CreateResult
      sig { params(token_record: IAuthenticationToken, token_value: String).void }
      def initialize(token_record, token_value)
        @token_record = T.let(token_record, IAuthenticationToken)
        @token_value = T.let(token_value, String)
      end

      # Ruby calls to_ary automatically when using multiple assignment (a, b = obj)
      # this lets us do: record, token = result.value if result.is_a?(GH::Result::Ok) (result.value would otherwise return the CreateResult instance)
      # and lets us avoid separate result.value.token_record & result.value.token_value assignment
      sig { returns(T::Array[T.untyped]) }
      def to_ary
        [token_record, token_value]
      end
    end

    DESTROY_BATCH_SIZE = 100
    DESTROY_LOOKUP_BATCH_SIZE = 100
    MAX_THROTTLE_RETRIES = 5

    ACCESS_TOKEN_PREFIX = "ghs_"

    REDIS_BACKEND_STATS_KEY = "authentication_token.redis"

    # Public: The Regexp describing the format of an AuthenticationToken's string
    # token value.
    TOKEN_PATTERN_GS1 = %r{
      \A                              # start
      #{ACCESS_TOKEN_PREFIX}     # the token format prefix
      [a-zA-Z0-9]{36}                 # the random portion and checksum
      \z                              # end
    }xi

    # legacy pattern
    TOKEN_PATTERN_V1 = %r{
      \A                 # start
      v1                 # the token format version
      \.                 # a period
      [a-f0-9]{40}       # the random portion of the token
      \z                 # end
    }xi

    # Stateless S2S token pattern: ghs_ prefix followed by a JWT (header.payload.signature)
    TOKEN_PATTERN_STATELESS = %r{
      \A                              # start
      #{ACCESS_TOKEN_PREFIX}     # the ghs_ token prefix
      [A-Za-z0-9_-]+                   # JWT header (base64url)
      \.                              # dot separator
      [A-Za-z0-9_-]+                   # JWT payload (base64url)
      \.                              # dot separator
      [A-Za-z0-9_-]+                   # JWT signature (base64url)
      \z                              # end
    }x

    # thread-local variable to track whether we've successfully warmed the connections to the authnd Redis instance.
    # this is used to inform whether we should increase our timeouts to accommodate increased connection times during
    # unicorn startup.
    @redis_warmed = T.let(false, T::Boolean)

    # Indicates whether the domain has established a successful connection to Redis (thread-local shared state).
    sig { returns(T::Boolean) }
    def self.redis_warmed?
      @redis_warmed
    end

    # Marks the domain as having established a successful connection to Redis (thread-local shared state).
    sig { void }
    def self.redis_warmed!
      @redis_warmed = true
    end

    # Checks if the given token matches the AuthenticationToken pattern
    #
    # token - The string to check
    #
    # Returns true if token follows the AuthenticationToken pattern,
    #   false if it doesn't
    sig { params(token: T.nilable(String)).returns(T::Boolean) }
    def self.matches_pattern?(token)
      !!(token =~ TOKEN_PATTERN_V1 ||
        token =~ TOKEN_PATTERN_GS1 ||
        token =~ TOKEN_PATTERN_STATELESS)
    end

    # Returns true if token is a stateless S2S JWT (ghs_ prefix + JWT structure)
    sig { params(token: T.nilable(String)).returns(T::Boolean) }
    def self.stateless_token?(token)
      !!(token =~ TOKEN_PATTERN_STATELESS)
    end

    # Hash token for server side persistence.
    sig { params(token: T.nilable(String)).returns(String) }
    def self.hash_token(token)
      ::AuthenticationToken.hash_token(token)
    end

    # Validate token checksum
    sig { params(token: T.nilable(String)).returns(T::Boolean) }
    def self.valid_checksum?(token)
      return false if TOKEN_PATTERN_V1.match?(token)
      ::AuthenticationToken.validate_token_checksum(token)
    end

    # finds an Authentication Token by its unhashed token value while manually forcing a read-only connection
    sig { params(token: String).returns(T.nilable(IAuthenticationToken)).checked(:always).on_failure(:raise) }
    def by_unhashed_token_ro(token)
      # Stateless tokens have no DB/Redis row — authenticate via authnd directly
      return stateless_token_metadata(token) if ServerToServerTokens::Domain.stateless_token?(token)

      hashed_token = AuthenticationToken.hash_token(token)

      if redis_enabled?
        result = read_from_redis(hashed_token)
        return result.ok if result.ok?
      end

      record =
        ActiveRecord::Base.connected_to(role: :reading) do
          ::AuthenticationToken.active.with_unhashed_token(token).first
        end

      if record.present? && redis_enabled?
        GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:read", "operation:by_unhashed_token_ro", "result:miss"])
      end

      record
    end

    # finds an Authentication Token by its unhashed token value
    # For stateless S2S JWTs, authenticates via authnd and returns a synthetic IAuthenticationToken.
    sig { params(token: String).returns(T.nilable(IAuthenticationToken)).checked(:always).on_failure(:raise) }
    def by_unhashed_token(token)
      # Stateless tokens have no DB/Redis row — authenticate via authnd directly
      return stateless_token_metadata(token) if ServerToServerTokens::Domain.stateless_token?(token)

      hashed_token = AuthenticationToken.hash_token(token)

      if redis_enabled?
        result = read_from_redis(hashed_token)
        return result.ok if result.ok?
      end

      record = ::AuthenticationToken.active.with_unhashed_token(token).first

      if record.present? && redis_enabled?
        GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:read", "operation:by_unhashed_token", "result:miss"])
      end

      record
    end

    # DEPRECATED: Use #by_unhashed_token instead. This method exists only for
    # batched lookups in token-scanning revocation and will be removed once
    # stateless tokens fully replace persisted tokens.
    #
    # finds Authentication Tokens by their hashed token values
    sig { params(hashed_tokens: T::Array[String], batch_size: Integer).returns(T::Hash[String, IAuthenticationToken]).checked(:always).on_failure(:raise) }
    def by_hashed_values(hashed_tokens, batch_size)
      accesses = T.let({}, T::Hash[String, IAuthenticationToken])

      redis_enabled = redis_enabled?

      hashed_tokens.each_slice(batch_size) do |slice|
        remaining = slice

        if redis_enabled
          redis_accesses = batch_read_from_redis(slice)
          accesses.merge!(redis_accesses)
          remaining = slice - redis_accesses.keys
        end

        next if remaining.empty?

        mysql_accesses = AuthenticationToken.where(hashed_value: remaining)
          .in_batches(of: batch_size)
          .each_record
          .index_by(&:hashed_value)

        if mysql_accesses.any?
          GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:read", "operation:by_hashed_values", "result:miss"], by: mysql_accesses.keys.count)
        end

        accesses.merge!(mysql_accesses)
      end
      accesses
    end

    # update an authentication token's expires_at
    sig { params(hashed_value: String, expires_at: T.nilable(String), entry_point: T.nilable(Symbol), record: T.nilable(IAuthenticationToken)).returns(GH::Result[IAuthenticationToken]).checked(:always).on_failure(:raise) }
    def extend_expires_at(hashed_value, expires_at, entry_point: nil, record: nil)
      if record&.is_a?(StatelessAuthenticationToken)
        expires_at = Time.zone.parse(expires_at) if expires_at.present?
        extend_s2s_stateless_token_resp = credential_manager.extend_stateless_app_token_expiration(
          hashed_value,
          expires_at: expires_at,
        )
        if extend_s2s_stateless_token_resp.success?
          extended_expires_at_timestamp = Time.zone.at(extend_s2s_stateless_token_resp.extended_expiration_to.seconds)
          record.expires_at = extended_expires_at_timestamp

          authenticatable = record.authenticatable
          # Skip extending the authenticatable here when the Hydro consumer handles it
          # via StatelessTokenExpirationExtensionProcessor.
          unless FeatureFlag.vexi.enabled?(:consume_stateless_token_expiration_extension_events, default: false)
            if authenticatable.respond_to?(:extend_expires_at) && T.unsafe(authenticatable).expires_at.present?
              extended_expires_at_for_authenticatable = [
                extended_expires_at_timestamp,
                T.unsafe(authenticatable).expires_at,
              ].max
              T.unsafe(authenticatable).extend_expires_at(extended_expires_at_for_authenticatable, entry_point: entry_point, token_last_eight: record.token_last_eight)
            end
          end

          return GH::Result::Ok.new(record)
        end
        GH::Result::Error.new(extend_s2s_stateless_token_resp.error)
      else
        record = ::AuthenticationToken.find_by(hashed_value: hashed_value)
        return GH::Result::Error::NotFound.new unless record
        result = AuthenticationToken.extend_expires_at(record, expires_at, entry_point: entry_point)

        if result.success? && redis_enabled?
          dual_write_extend_to_redis(record)
        end

        return GH::Result::Ok.new(record) if result.success?
        GH::Result::Error.new(result.message)
      end
    end

    # Called by Api::IntegrationInstallations#delete & RevokeAuthenticationTokenJob
    sig { params(token: String).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def destroy_by_hashed_token(token)
      record = ::AuthenticationToken.active.find_by(hashed_value: token)
      return GH::Result::Error::NotFound.new unless record

      if redis_enabled?
        dual_write_destroy_to_redis(record)
      end

      record.destroy
      GH::Result::Ok.new(true)
    end

    # Called by Api::IntegrationInstallations#delete & RevokeAuthenticationTokenJob
    sig { params(token: String, reason: String).returns(GH::Result[T::Boolean]).checked(:always).on_failure(:raise) }
    def destroy_by_unhashed_token(token, reason:)
      if ServerToServerTokens::Domain.stateless_token?(token)
        revoke_s2s_stateless_token_resp = credential_manager.revoke_stateless_app_token(token, reason: reason)
        return GH::Result::Ok.new(true) if revoke_s2s_stateless_token_resp.success?
        GH::Result::Error.new(revoke_s2s_stateless_token_resp.message)
      else
        GH::Result::Error.new("Only stateless tokens can be revoked by unhashed value. Use destroy_by_hashed_token for persisted tokens.")
      end
    end

    # delete all AuthenticationTokens associated with the authenticatable
    sig { params(authenticatable_type: String, authenticatable_id: Integer).returns(GH::Result[Integer]).checked(:always).on_failure(:raise) }
    def destroy_by_authenticatable(authenticatable_type, authenticatable_id)
      deleted_count = 0
      selected_count = T.let(0, Integer)

      loop do
        selected_count = 0

        batch_deleted = AuthenticationToken.throttle_with_retry(max_retry_count: MAX_THROTTLE_RETRIES) do
          # No destroy callbacks on this model — delete_all avoids 100 individual
          # DELETE round-trips per batch and eliminates the in_batches ORDER BY id
          # filesort that was causing I/O amplification on the lodge cluster.
          AuthenticationToken.with_write do
            if redis_enabled?
              hashed_values = AuthenticationToken
                .where(
                  authenticatable_type: authenticatable_type,
                  authenticatable_id: authenticatable_id
                )
                .limit(DESTROY_BATCH_SIZE)
                .pluck(:hashed_value)

              selected_count = hashed_values.length

              keys = hashed_values.map { |hv| RedisAuthenticationToken.key_for_hashed_value(hv) }

              begin
                ServerToServerToken::Redis.del(keys)
              rescue Redis::BaseError => e
                GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:destroy", "result:failure"])
                Failbot.report!(e)
              end

              AuthenticationToken.where(hashed_value: hashed_values).delete_all
            else
              ids = AuthenticationToken
                .where(
                  authenticatable_type: authenticatable_type,
                  authenticatable_id: authenticatable_id
                )
                .limit(DESTROY_BATCH_SIZE)
                .pluck(:id)

              selected_count = ids.length

              AuthenticationToken.where(id: ids).delete_all
            end
          end
        end

        deleted_count += batch_deleted
        break if selected_count < DESTROY_BATCH_SIZE
      end

      GH::Result::Ok.new(deleted_count)
    end

    # create a new Authentication Token
    sig do params(authenticatable_id: Integer, authenticatable_type: String, span_attributes: T::Hash[String, String], code_path: T.nilable(String), integration_id: T.nilable(Integer))
      .returns(GH::Result[CreateResult]).checked(:always).on_failure(:raise)
    end
    def create(authenticatable_id, authenticatable_type, span_attributes, code_path: nil, integration_id: nil)
      if integration_id
        create_stateless(authenticatable_id, authenticatable_type, span_attributes, integration_id: integration_id)
      else
        create_persisted(authenticatable_id, authenticatable_type, span_attributes, code_path: code_path)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ArgumentError, NameError => e
      GH::Result::Error.new(e.message)
    end

    # Authenticates a server to server token (using authnd's authenticate API)
    #
    # This method should be used when you know that the access token is a ServerToServerToken
    # but there is no difference in the underlying authenticate call when you don't know which type of access token you have
    sig { params(calling_service: String, token: String).returns(::Authnd::Response).checked(:always).on_failure(:raise) }
    def authenticate(calling_service, token)
      ::ServerToServerToken::Authenticator.perform(calling_service, token)
    end

    # Authenticates a stateless S2S JWT via authnd and returns a hydrated IAuthenticationToken.
    # Returns nil if authentication fails without returning attributes (e.g. invalid JWT, expired token).
    # When authnd defers an auth error (e.g. suspended integration) it still returns attributes,
    # so we build the token metadata regardless — the auth policy is enforced downstream.
    sig { params(token: String).returns(T.nilable(IAuthenticationToken)).checked(:always).on_failure(:raise) }
    def stateless_token_metadata(token)
      resp = authenticate("github/authnd", token)
      # Hard failures (invalid JWT, expired, installation not found) return no attributes — bail out.
      # Deferred failures (suspended, spammy) return attributes alongside a non-success result.
      return nil if resp.attributes.nil? || resp.attributes.empty?

      expires_at = resp.attributes[::Authnd::Client::Attributes::CREDENTIAL_EXPIRES_AT]
      installation_id = resp.attributes[::Authnd::Client::Attributes::INSTALLATION_ID]
      scoped_id = resp.attributes[::Authnd::Client::Attributes::SCOPED_INSTALLATION_ID]
      scoped_type = resp.attributes[::Authnd::Client::Attributes::SCOPED_INSTALLATION_TYPE]
      issued_at = resp.attributes[::Authnd::Client::Attributes::CREDENTIAL_ISSUED_AT]

      authenticatable_id = scoped_id || installation_id
      authenticatable_type = scoped_type || "IntegrationInstallation"
      credential_id = resp.attributes[::Authnd::Client::Attributes::CREDENTIAL_ID]
      StatelessAuthenticationToken.new(
        authenticatable_id: authenticatable_id.to_i,
        authenticatable_type: authenticatable_type.to_s,
        created_at: issued_at ? Time.zone.at(issued_at.to_f) : Time.current,
        expires_at: expires_at ? Time.zone.at(expires_at.to_f) : AuthenticationToken::EXPIRATION_WINDOW.from_now,
        token_id: resp.attributes[::Authnd::Client::Attributes::STATELESS_CREDENTIAL_ID],
        hashed_value: AuthenticationToken.hash_token(token),
        raw_token: token,
        token_last_eight: token.last(8),
        credential_id: credential_id&.to_i,
      )
    end

    # Authenticates a S2S token with the token_result format needed for the GitHub::Authentication::Attempt try_auth -> try_access_token_auth flow
    sig { params(token: String, auth_options: T.untyped).returns(GitHub::Authentication::Result).checked(:always).on_failure(:raise) }
    def token_authenticate(token, auth_options)
      enable_experiment = !auth_options&.delete(:disable_experiments)
      if enable_experiment && FeatureFlag.vexi.enabled?(:authnd_experiment_server_to_server_token, default: false)
        try_server_to_server_token_auth_experiment(token, auth_options)
      else
        GitHub.auth.access_token_authenticate(token, **auth_options)
      end
    end

    # Check to see if the domain is using redis.
    sig { returns(T::Boolean) }
    def redis_enabled?
      # GHES or Proxima
      return false if GitHub.single_or_multi_tenant_enterprise?

      true
    end

    private

    sig { params(hashed_token: String).returns(GH::Result[RedisAuthenticationToken]) }
    def read_from_redis(hashed_token)
      raw = ServerToServerToken::Redis.get(RedisAuthenticationToken.key_for_hashed_value(hashed_token))

      unless raw
        GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:read", "operation:read_from_redis", "result:miss"])
        return GH::Result::Error::NotFound.new
      end

      self.class.redis_warmed! unless self.class.redis_warmed?

      data = MessagePack.unpack(raw)
      created_at = Time.zone.at(data["created_at"])

      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:read", "result:hit", "operation:read_from_redis"])

      GH::Result::Ok.new(
        RedisAuthenticationToken.new(
          authenticatable_id: data["authenticatable_id"],
          authenticatable_type: data["authenticatable_type"],
          created_at: Time.zone.at(data["created_at"]),
          hashed_value: hashed_token,
          id: data["id"],
          token_last_eight: data["token_last_eight"],
        )
      )
    rescue MessagePack::UnpackError, Redis::BaseError => e
      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:read", "result:failure", "operation:read_from_redis"])
      Failbot.report!(e)

      GH::Result::Error.new(e.message, e)
    end

    sig { params(hashed_tokens: T::Array[String]).returns(T::Hash[String, RedisAuthenticationToken]) }
    def batch_read_from_redis(hashed_tokens)
      keys = hashed_tokens.map do |hashed_token|
        RedisAuthenticationToken.key_for_hashed_value(hashed_token)
      end

      result = T.let({}, T::Hash[String, RedisAuthenticationToken])

      raw = ServerToServerToken::Redis.mget(keys)
      return result if raw.empty?
      self.class.redis_warmed! unless self.class.redis_warmed?

      hashed_tokens.each_with_index do |hashed_token, index|
        msg = raw[index]
        next if msg.nil?

        data = MessagePack.unpack(msg)

        result[hashed_token] =
          RedisAuthenticationToken.new(
            authenticatable_id: data["authenticatable_id"],
            authenticatable_type: data["authenticatable_type"],
            created_at: Time.zone.at(data["created_at"]),
            hashed_value: hashed_token,
            id: data["id"],
            token_last_eight: data["token_last_eight"],
          )
      end

      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:read", "result:success", "operation:batch_read_from_redis"])

      result
    rescue MessagePack::UnpackError, Redis::BaseError => e
      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:read", "result:failure", "operation:batch_read_from_redis"])
      Failbot.report!(e)

      {}
    end

    sig { params(record: IAuthenticationToken).void }
    def dual_write_to_redis(record)
      pack = MessagePack.pack({
        "id" => record.id,
        "authenticatable_id" => record.authenticatable_id,
        "authenticatable_type" => record.authenticatable_type,
        "created_at" => record.created_at.to_i,
        "token_last_eight" => record.token_last_eight,
      })

      ServerToServerToken::Redis.set(
        key: RedisAuthenticationToken.key_for_hashed_value(record.hashed_value),
        value: pack,
        px: RedisAuthenticationToken::EXPIRATION_WINDOW
      )

      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:create", "result:success"])

      self.class.redis_warmed! unless self.class.redis_warmed?
    rescue Redis::BaseError => e
      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:create", "result:failure"])
      Failbot.report!(e)
    end

    sig { params(record: AuthenticationToken).void }
    def dual_write_extend_to_redis(record)
      remaining_ttl_ms = ((record.expires_at_timestamp.to_i - Time.zone.now.to_i) * 1000)
      return if remaining_ttl_ms <= 0

      pack = MessagePack.pack({
        "id" => record.id,
        "authenticatable_id" => record.authenticatable_id,
        "authenticatable_type" => record.authenticatable_type,
        "created_at" => record.created_at.to_i,
        "token_last_eight" => record.token_last_eight,
      })

      ServerToServerToken::Redis.set(
        key: RedisAuthenticationToken.key_for_hashed_value(record.hashed_value),
        value: pack,
        px: remaining_ttl_ms,
      )

      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:extend", "result:success"])

      self.class.redis_warmed! unless self.class.redis_warmed?
    rescue Redis::BaseError => e
      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:extend", "result:failure"])
      Failbot.report!(e)
    end

    sig { params(record: AuthenticationToken).void }
    def dual_write_destroy_to_redis(record)
      ServerToServerToken::Redis.del([
        RedisAuthenticationToken.key_for_hashed_value(record.hashed_value)
      ])

      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:destroy", "result:success"])

      self.class.redis_warmed! unless self.class.redis_warmed?
    rescue Redis::BaseError => e
      GitHub.dogstats.increment(REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:destroy", "result:failure"])
      Failbot.report!(e)
    end

    sig { params(token: String, access_token_auth_options: T::Hash[Symbol, T.untyped]).returns(GitHub::Authentication::Result) }
    def try_server_to_server_token_auth_experiment(token, access_token_auth_options)
      e = GitHub::Authnd::Experiment::new "authnd.attempt.try_server_to_server_token_auth"

      e.use { GitHub.auth.access_token_authenticate(token, **access_token_auth_options) }

      e.try do
        GitHub.auth.access_token_authenticate_authnd(token,
          **access_token_auth_options.merge(
            allow_server_to_server: true,
            mesh_available: true,
          )
        )
      end

      e.compare do |control, candidate|
        e.compare_server_to_server_token_experiment_result(control, candidate)
      end

      e.clean do |value|
        e.clean_server_to_server_token_experiment_result(value)
      end

      e.ignore do |control, candidate|
        e.ignore_server_to_server_token_experiment(token, control, candidate)
      end

      e.run
    end

    sig { params(calling_service: String).returns(::Authnd::Client::CredentialManager) }
    def credential_manager(calling_service: "github/account_login")
      ::GitHub::Authnd.credential_manager(calling_service)
    end

    sig { params(authenticatable_type: String, authenticatable_id: Integer).returns(Authnd::Proto::AuthorizationContext) }
    def authorization_context_for(authenticatable_type, authenticatable_id)
      case authenticatable_type
      when "IntegrationInstallation"
        T.unsafe(Authnd::Proto::AuthorizationContext).new(
          installation: T.unsafe(Authnd::Proto::AuthorizationContext::Installation).new(id: authenticatable_id),
        )
      when "ScopedIntegrationInstallation"
        T.unsafe(Authnd::Proto::AuthorizationContext).new(
          scoped_installation: T.unsafe(Authnd::Proto::AuthorizationContext::ScopedInstallation).new(id: authenticatable_id),
        )
      when "SiteScopedIntegrationInstallation"
        T.unsafe(Authnd::Proto::AuthorizationContext).new(
          site_scoped_installation: T.unsafe(Authnd::Proto::AuthorizationContext::SiteScopedInstallation).new(id: authenticatable_id),
        )
      else
        raise ArgumentError, "Unknown authenticatable_type: #{authenticatable_type}"
      end
    end

    sig { params(authenticatable_id: Integer, authenticatable_type: String, span_attributes: T::Hash[String, String], integration_id: Integer).returns(GH::Result[CreateResult]) }
    def create_stateless(authenticatable_id, authenticatable_type, span_attributes, integration_id:)
      GitHub.tracer.in_span("ServerToServerTokens::Domain#s2s_stateless_token_authnd_creation", kind: :internal) do |span|
        span.add_attributes(span_attributes)
        expires_at = AuthenticationToken::EXPIRATION_WINDOW.from_now
        attributes = {
          "application.id" => integration_id,
        }
        issue_s2s_stateless_token_response = credential_manager.issue_stateless_app_token(
          :TOKEN_TYPE_S2S,
          attributes,
          authorization_context: authorization_context_for(authenticatable_type, authenticatable_id),
          expires_at: expires_at,
        )
        if issue_s2s_stateless_token_response.success?
          token = issue_s2s_stateless_token_response.token
          now = Time.current
          token_record = StatelessAuthenticationToken.new(
            authenticatable_id: authenticatable_id,
            authenticatable_type: authenticatable_type,
            created_at: now,
            expires_at: expires_at,
            hashed_value: AuthenticationToken.hash_token(token),
            raw_token: token,
            token_id: issue_s2s_stateless_token_response.token_id,
            token_last_eight: token.last(8),
          )
          next GH::Result::Ok.new(CreateResult.new(token_record, token))
        end

        GH::Result::Error.new(issue_s2s_stateless_token_response.error)
      end
    rescue ::Authnd::Proto::Error, Faraday::Error => err
      Failbot.report!(err)
      GH::Result::Error.new(err.message)
    end

    sig { params(authenticatable_id: Integer, authenticatable_type: String, span_attributes: T::Hash[String, String], code_path: T.nilable(String)).returns(GH::Result[CreateResult]) }
    def create_persisted(authenticatable_id, authenticatable_type, span_attributes, code_path: nil)
      record, token = AuthenticationToken.create_for(authenticatable_id, authenticatable_type, span_attributes, code_path: code_path)

      if redis_enabled?
        dual_write_to_redis(record)
      end
      GH::Result::Ok.new(CreateResult.new(record, token))
    end
  end
end
