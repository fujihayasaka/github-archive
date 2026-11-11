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
      token_id: String,
      token_last_eight: String,
    ).void
  end
  def initialize(authenticatable_id:, authenticatable_type:, created_at:, expires_at:, hashed_value:, token_id:, token_last_eight:)
    @authenticatable_id = T.let(authenticatable_id, Integer)
    @authenticatable_type = T.let(authenticatable_type, String)
    @created_at = T.let(created_at, Time)
    @expires_at = T.let(expires_at, Time)
    @hashed_value = T.let(hashed_value, String)
    @token_id = T.let(token_id, String)
    @token_last_eight = T.let(token_last_eight, String)
    @valid_after = T.let(nil, T.nilable(Time))
  end

  sig { override.returns(Integer) }
  def id
    # Derive a deterministic numeric ID from the UUID token_id using a stable
    # digest. We take the first 15 hex characters (60 bits) of the SHA-256
    # digest to stay well within a signed 64-bit integer range while still
    # providing strong collision resistance.
    T.must(Digest::SHA256.hexdigest(@token_id).slice(0, 15)).to_i(16)
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

  sig { override.returns(T::Boolean) }
  def expired?
    Time.current >= @expires_at
  end

  sig { override.returns(T.nilable(Time)) }
  def valid_after
    @valid_after
  end

  sig { override.params(time: T.nilable(Time)).void }
  def valid_after=(time)
    @valid_after = time
  end

  # Returns the unique token identifier from authnd.
  sig { returns(String) }
  def token_id
    @token_id
  end
end
