# typed: strict
# frozen_string_literal: true

class RedisAuthenticationToken
  include ServerToServerTokens::IAuthenticationToken
  include GitHub::Memoizer

  EXPIRATION_WINDOW = 3_600_000 # 1 hour in milliseconds
  KEY_PREFIX = "app_security:s2s"
  DEFAULT_ID = 0

  sig { params(hashed_value: String).returns(String) }
  def self.key_for_hashed_value(hashed_value)
    "#{KEY_PREFIX}:#{hashed_value}"
  end

  # Creates a RedisAuthenticationToken and persists it to Redis.
  # Mirrors the AuthenticationToken.create_for interface.
  #
  # Returns a tuple of [RedisAuthenticationToken, token_value String].
  sig { params(authenticatable_id: Integer, authenticatable_type: String, span_attributes: T::Hash[String, String], code_path: T.nilable(String)).returns([RedisAuthenticationToken, String]) }
  def self.create_for(authenticatable_id, authenticatable_type, span_attributes, code_path: AuthenticationToken::UNKNOWN_CODE_PATH)
    GitHub.tracer.in_span("RedisAuthenticationToken.create_for", kind: :internal) do |span|
      token_value, hashed_token = AuthenticationToken.generate_random_token_pair

      token_record = new(
        authenticatable_id: authenticatable_id,
        authenticatable_type: authenticatable_type,
        created_at: Time.zone.now,
        hashed_value: hashed_token,
        id: DEFAULT_ID,
        token_last_eight: token_value.last(8),
      )

      ServerToServerToken::Redis.set(
        key: key_for_hashed_value(hashed_token),
        value: pack(token_record),
        px: EXPIRATION_WINDOW
      )

      GitHub.dogstats.increment(::ServerToServerTokens::Domain::REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:create", "result:success"])

      span.add_attributes(span_attributes)

      GitHub.dogstats.increment(AuthenticationToken::CREATE_FOR_STATS_KEY, tags: [
        "code_path:#{code_path}", "authenticatable_type:#{authenticatable_type}"
      ])

      [token_record, token_value]
    end
  end

  # Extends the expiration of a Redis-backed token.
  # Mirrors the AuthenticationToken.extend_expires_at interface.
  #
  # Returns an AuthenticationToken::ExtensionResult.
  sig { params(record: ServerToServerTokens::IAuthenticationToken, expires_at: T.nilable(String), entry_point: T.nilable(Symbol)).returns(AuthenticationToken::ExtensionResult) }
  def self.extend_expires_at(record, expires_at, entry_point:)
    extended_expires_at_timestamp =
      if expires_at.present?
        Time.parse(expires_at)
      else
        AuthenticationToken::EXPIRATION_WINDOW.from_now
      end

    if extended_expires_at_timestamp > (T.must(record.created_at) + 24.hours)
      return AuthenticationToken::ExtensionResult.failed(:end_of_life)
    elsif extended_expires_at_timestamp > AuthenticationToken::EXPIRATION_WINDOW.from_now
      return AuthenticationToken::ExtensionResult.failed(:expires_at_too_long)
    elsif extended_expires_at_timestamp <= Time.zone.now
      return AuthenticationToken::ExtensionResult.failed(:expires_at_in_past)
    end

    remaining_ttl_ms = ((extended_expires_at_timestamp.to_i - Time.zone.now.to_i) * 1000)

    was_extended = ServerToServerToken::Redis.set(
      key: key_for_hashed_value(record.hashed_value),
      value: pack(record),
      px: remaining_ttl_ms,
      xx: true
    )

    unless was_extended
      GitHub.dogstats.increment(::ServerToServerTokens::Domain::REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:extend", "result:not_found"])
      return AuthenticationToken::ExtensionResult.failed(:not_found)
    end

    GitHub.dogstats.increment(::ServerToServerTokens::Domain::REDIS_BACKEND_STATS_KEY, tags: ["mode:write", "operation:extend", "result:success"])

    authenticatable = record.authenticatable

    case authenticatable
    when ScopedIntegrationInstallation, SiteScopedIntegrationInstallation
      if authenticatable.expires_at.present?
        extended_expires_at_for_authenticatable = [
          extended_expires_at_timestamp,
          authenticatable.expires_at,
        ].max

        authenticatable.extend_expires_at(extended_expires_at_for_authenticatable, entry_point: entry_point, token_last_eight: record.token_last_eight)
      end
    end

    AuthenticationToken::ExtensionResult.success
  end

  sig { params(record: ServerToServerTokens::IAuthenticationToken).returns(String) }
  def self.pack(record)
    MessagePack.pack({
      "id" => record.id,
      "authenticatable_id" => record.authenticatable_id,
      "authenticatable_type" => record.authenticatable_type,
      "created_at" => T.must(record.created_at).to_i,
      "token_last_eight" => record.token_last_eight,
    })
  end

  sig { params(authenticatable_id: Integer, authenticatable_type: String, created_at: ActiveSupport::TimeWithZone, hashed_value: String, id: Integer, token_last_eight: String).void }
  def initialize(authenticatable_id:, authenticatable_type:, created_at:, hashed_value:, id:, token_last_eight:)
    @authenticatable_id = T.let(authenticatable_id, Integer)
    @authenticatable_type = T.let(authenticatable_type, String)
    @created_at = T.let(created_at, ActiveSupport::TimeWithZone)
    @hashed_value = T.let(hashed_value, String)
    @id = T.let(id, Integer)
    @token_last_eight = T.let(token_last_eight, String)
    @valid_after = T.let(nil, T.nilable(Time))
  end

  sig { override.returns(Integer) }
  def authenticatable_id
    @authenticatable_id
  end

  sig { override.returns(String) }
  def authenticatable_type
    @authenticatable_type
  end

  sig do
    returns(T.any(
      IntegrationInstallation,
      ScopedIntegrationInstallation,
      SiteScopedIntegrationInstallation,
      NilClass
    ))
  end
  def authenticatable
    authenticatable_class.find_by(id: @authenticatable_id)
  end

  sig { override.returns(T.nilable(Time)) }
  def created_at
    @created_at.to_time
  end

  sig { override.returns(T::Boolean) }
  def expired?
    expires_at_timestamp.nil? || Time.current >= expires_at_timestamp
  end

  sig { override.returns(T.nilable(Time)) }
  memoize def expires_at_timestamp
    ttl = ServerToServerToken::Redis.ttl(self.class.key_for_hashed_value(hashed_value))

    case ttl
    when -2, -1
      nil
    else
      (Time.current + ttl).to_time
    end
  rescue => e
    Failbot.report!(e)

    nil
  end

  sig { override.returns(String) }
  def hashed_value
    @hashed_value
  end

  sig { override.returns(Integer) }
  def id
    @id
  end

  sig { override.returns(String) }
  def token_last_eight
    @token_last_eight
  end

  sig { override.returns(T.nilable(Time)) }
  def valid_after
    @valid_after
  end

  sig { override.params(time: T.any(Float, NilClass, Time)).void }
  def valid_after=(time)
    if time.is_a?(Float)
      time = Time.zone.at(time).to_time
    end

    @valid_after = time
  end

  sig { returns(RedisAuthenticationToken) }
  def reload
    remove_instance_variable(:@all_memoized) if instance_variable_defined?(:@all_memoized)
    self
  end

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    return false unless other.is_a?(RedisAuthenticationToken)

    id == other.id &&
      hashed_value == other.hashed_value &&
      authenticatable_id == other.authenticatable_id &&
      authenticatable_type == other.authenticatable_type &&
      token_last_eight == other.token_last_eight
  end
end
