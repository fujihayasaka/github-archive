# typed: strict
# frozen_string_literal: true

require "active_support/core_ext"

# Code for HMAC verification.
#
# This is the core HMAC verification code. It is designed to be used as
# static module methods that can be called from controllers or any
# other context for that matter.
module OctoCore::Auth::Hmac
  extend T::Helpers
  extend T::Sig

  class Env < OctoCore::Env::Base
    define_env_variable(:internal_api_hmac_key, :string, required: true)
    define_env_variable(:internal_api_secondary_hmac_key, :string)
  end

  abstract!

  REQUEST_HMAC_INTERVAL = T.let(10.minutes, ActiveSupport::Duration)
  HMAC_ALGORITHM = "sha256"

  # Takes the HMAC of an integer epoch timestamp with key.
  sig { params(time: Time, key: String).returns(String) }
  def generate_hmac(time, key)
    timestamp = time.to_i.to_s

    hmac = OpenSSL::HMAC.hexdigest(
      HMAC_ALGORITHM,
      key, timestamp
    )
    "#{timestamp}.#{hmac}"
  end

  sig { params(received_hmac: String, valid_hmac_keys: T.nilable(T::Array[String])).returns([Symbol, T.nilable(String)]) }
  def verify_hmac(received_hmac, valid_hmac_keys = internal_api_hmac_keys)
    return [:no_key, nil] unless valid_hmac_keys.present?
    return [:empty, nil] if received_hmac.blank?

    timestamp, hmac = received_hmac.split(".", 2)
    return [:invalid, nil] if timestamp.blank? || hmac.blank?

    timestamp = timestamp.to_i
    return [:invalid_timestamp, nil] unless valid_timestamp?(timestamp)

    matched_key = matching_key(received_hmac, valid_hmac_keys, timestamp)
    status = matched_key ? :success : :fail
    [status, matched_key]
  end

  sig { returns(T::Array[String]) }
  def internal_api_hmac_keys
    return T.cast(@internal_api_hmac_keys, T::Array[String]) if defined?(@internal_api_hmac_keys)

    array = T.cast([
      Env.internal_api_hmac_key,
      Env.internal_api_secondary_hmac_key
    ].compact_blank, T::Array[String])

    @internal_api_hmac_keys = T.let(array, T.nilable(T::Array[String]))

    T.cast(@internal_api_hmac_keys, T::Array[String])
  end

  sig { params(timestamp: Integer).returns(T::Boolean) }
  def valid_timestamp?(timestamp)
    timestamp > REQUEST_HMAC_INTERVAL.ago.to_i &&
      timestamp < REQUEST_HMAC_INTERVAL.from_now.to_i
  end

  private

  sig do
    params(received_hmac: String, valid_hmac_keys: T::Array[String], timestamp: Integer)
    .returns(T.nilable(String))
  end
  def matching_key(received_hmac, valid_hmac_keys, timestamp)
    time = Time.at(timestamp)
    valid_hmac_keys.detect do |valid_hmac_key|
      OctoCore::SecurityUtils.secure_compare(
        received_hmac,
        generate_hmac(time, valid_hmac_key),
      )
    end
  end

  extend self
end
