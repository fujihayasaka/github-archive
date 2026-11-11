# typed: strict
# frozen_string_literal: true

class StatelessAuthenticationToken
  include ServerToServerTokens::IAuthenticationToken

  sig do
    params(
      authenticatable_id: Integer,
      authenticatable_type: String,
      created_at: Time,
      expires_at: Time,
      hashed_value: String,
      raw_token: String,
      token_id: String,
      token_last_eight: String,
      credential_id: T.nilable(Integer),
    ).void
  end
  def initialize(authenticatable_id:, authenticatable_type:, created_at:, expires_at:, hashed_value:, raw_token:, token_id:, token_last_eight:, credential_id: nil)
    @authenticatable_id = T.let(authenticatable_id, Integer)
    @authenticatable_type = T.let(authenticatable_type, String)
    @created_at = T.let(created_at, Time)
    @expires_at = T.let(expires_at, Time)
    @hashed_value = T.let(hashed_value, String)
    @raw_token = T.let(raw_token, String)
    @token_id = T.let(token_id, String)
    @token_last_eight = T.let(token_last_eight, String)
    @credential_id = T.let(credential_id, T.nilable(Integer))
    @valid_after = T.let(nil, T.nilable(Time))
  end

  FNV1A_64_OFFSET = 0xcbf29ce484222325
  FNV1A_64_PRIME = 0x100000001b3
  MASK_64 = 0xFFFFFFFFFFFFFFFF

  # Public: Derive a deterministic positive int64 from a JTI string using FNV-1a 64-bit hash.
  # Must match CredentialIDFromJTI() in authnd (https://github.com/github/authnd/blob/f6b2acb29639e581452fdc7c9c0700caae30eb6d/internal/common/tokens/util.go#L36)
  # so that credential.id is consistent across authnd responses, audit logs, and the dotcom model.
  sig { params(jti: String).returns(Integer) }
  def self.synthetic_id(jti)
    hash = FNV1A_64_OFFSET
    jti.each_byte { |b| hash = ((hash ^ b) * FNV1A_64_PRIME) & MASK_64 }
    hash & 0x7FFFFFFFFFFFFFFF
  end

  sig { override.returns(Integer) }
  def id
    @credential_id || self.class.synthetic_id(@token_id)
  end

  sig { override.returns(Integer) }
  def authenticatable_id
    @authenticatable_id
  end

  sig { override.returns(String) }
  def authenticatable_type
    @authenticatable_type
  end

  sig { override.returns(String) }
  def hashed_value
    @hashed_value
  end

  sig { override.returns(String) }
  def token_last_eight
    @token_last_eight
  end

  sig { override.returns(T.nilable(Time)) }
  def created_at
    @created_at
  end

  sig { override.returns(T.nilable(Time)) }
  def expires_at_timestamp
    @expires_at
  end

  sig { params(time: Time).void }
  def expires_at=(time)
    @expires_at = time
  end

  sig { override.returns(T::Boolean) }
  def expired?
    Time.current >= @expires_at
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

  # Returns the unique token identifier from authnd.
  sig { returns(String) }
  def token_id
    @token_id
  end

  sig { returns(String) }
  def token
    @raw_token
  end

  # Re-fetches token metadata from authnd so that all fields
  # reflect server-side state, analogous to ActiveRecord#reload.
  sig { returns(T.self_type) }
  def reload
    refreshed = ServerToServerTokens.domain.by_unhashed_token_ro(@raw_token)
    if refreshed.is_a?(StatelessAuthenticationToken)
      @authenticatable_id = refreshed.authenticatable_id
      @authenticatable_type = refreshed.authenticatable_type
      @created_at = T.must(refreshed.created_at)
      @expires_at = T.must(refreshed.expires_at_timestamp)
      @token_last_eight = refreshed.token_last_eight
    end
    self
  end
end
