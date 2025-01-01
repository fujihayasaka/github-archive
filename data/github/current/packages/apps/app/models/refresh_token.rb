# typed: true
# frozen_string_literal: true

class RefreshToken < ApplicationRecord::Domain::IntegrationsCollab
  TOKEN_PREFIX = "ghr_"
  TOKEN_BYTES  = 70

  DEFAULT_EXPIRY = 6.months
  MAX_EXPIRY = 6.months

  # Public: The Regexp describing the format of an RefreshToken's string
  # token value.
  TOKEN_PATTERN_GR1 = %r{
    \A                              # start
    #{TOKEN_PREFIX}     # the token format prefix
    [a-zA-Z0-9]{76}                 # the random portion and checksum
    \z                              # end
  }xi

  GRANT_TYPE = "refresh_token"

  attribute :expires_at, :utc_timestamp

  attr_accessor :expiry, :token

  belongs_to :refreshable, polymorphic: true

  extend GitHub::Encoding
  force_utf8_encoding :hashed_token

  def self.valid_grant_type?(type)
    GRANT_TYPE == type
  end

  before_save :set_hashed_token
  before_save :set_expires_at

  scope :active, -> { where("expires_at > ?", Time.now.to_i) }
  scope :inactive, -> { where("expires_at < ?", Time.now.to_i) }

  class LookupResult
    def self.empty(reason:, new_format: false)
      new(token: nil, reason: reason, new_format: new_format)
    end

    attr_reader :reason, :token

    def initialize(token:, reason:, new_format:)
      @token = token
      @reason = reason
      @new_format = new_format
    end

    def expired?
      reason == :expired
    end

    def new_format?
      @new_format
    end

    def valid_checksum?
      !(reason == :invalid_checksum)
    end
  end

  def self.hash_token(token)
    AccessTokenGeneratable.hash_token(token)
  end

  def self.valid_checksum?(token)
    AccessTokenGeneratable.valid_checksum?(token)
  end

  def self.for_plaintext_token(token, application:)
    if token.nil? || token.empty?
      return LookupResult.empty(reason: :no_token)
    end
    if application.nil?
      return LookupResult.empty(reason: :no_application)
    end

    # how long do we want to track the new token format for?
    is_new_format = TOKEN_PATTERN_GR1.match?(token)
    valid_checksum = is_new_format && valid_checksum?(token)

    if is_new_format && !valid_checksum
      return LookupResult.empty(
        reason: :invalid_checksum,
        new_format: true
      )
    end

    refresh_token = includes(refreshable: :application).find_by(hashed_token: hash_token(token))

    returnable_token, reason = if refresh_token && !refresh_token.expired? && refresh_token.refreshable&.application == application
      [refresh_token, :success]
    elsif !refresh_token
      [nil, :not_found]
    elsif refresh_token.expired?
      [nil, :expired]
    elsif refresh_token.refreshable&.application != application
      [nil, :mismatched_application]
    else
      [nil, :unknown]
    end

    LookupResult.new(
      token: returnable_token,
      reason: reason,
      new_format: is_new_format,
    )
  end

  def redeem(entry_point:)
    access_token = refreshable.reset_with_expiry(expires_at: OauthAccess::DEFAULT_INSTALLATION_TOKEN_EXPIRY.from_now)
    reset_token(entry_point: entry_point)
    [access_token, token]
  end

  def expired?
    Time.now > expires_at
  end

  def expires_in
    return 0 if expires_at.nil?
    return DEFAULT_EXPIRY.to_i if new_record?

    expires_at.to_i - Time.now.utc.to_i
  end

  # Public: Reset the refresh token.
  #
  # Returns String token.
  def reset_token(entry_point:)
    self.hashed_token = nil
    self.expires_at = T.unsafe(nil)

    save!

    # Extend the life of the scoped installation on the
    # refreshable.
    if (installation = refreshable.try(:installation))
      installation.extend_expires_at(self.expires_at, entry_point: entry_point)
    end

    token
  end

  private

  def set_hashed_token
    return if hashed_token

    self.token, self.hashed_token = AccessTokenGeneratable.generate_random_token_pair(
      access_token_prefix: TOKEN_PREFIX,
      access_token_bytes: TOKEN_BYTES,
    )
  end

  def set_expires_at
    return if T.unsafe(self).expires_at
    self.expiry = DEFAULT_EXPIRY if expiry && expiry > MAX_EXPIRY
    self.expiry ||= DEFAULT_EXPIRY

    T.unsafe(self).expires_at ||= expiry.from_now
  end
end
