# typed: true
# frozen_string_literal: true

class OtpSmsTiming < ApplicationRecord::Collab
  extend T::Sig

  def self.by_timing_key(timing_key)
    where(timing_key: timing_key).first
  end

  def self.expired_outstanding
    where("created_at < ?", totp_cutoff_time)
  end

  def self.record_outstanding(key, provider, user_id)
    ActiveRecord::Base.connected_to(role: :writing) do
      create(
        timing_key: key,
        provider: provider,
        user_id: user_id,
      )
    end
  end

  def self.resolve(id)
    ActiveRecord::Base.connected_to(role: :writing) do
      delete(id)
    end
  end

  # The earliest time that a TOTP could have been generated and still be valid.
  #
  sig { returns(Time) }
  def self.totp_cutoff_time
    # How many 30 second intervals back codes are valid for.
    intervals = (TwoFactorCredential::ALLOWABLE_DRIFT / 30.0).ceil

    # If t=15, new OTPs were generated at 0, -30, -60, -90, -120....
    # t - 90 = -75. A code generated at t=-75 would have been from the -90
    # interval, so we need to look at least intervals+1 intervals ago.
    intervals += 1

    (intervals * 30).seconds.ago
  end
end
