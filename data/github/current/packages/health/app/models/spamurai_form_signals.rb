# typed: true
# frozen_string_literal: true

# The timestamp secrets can be safely rolled with the following steps:
# - Add a new token to SPAMURAI_TIMESTAMP_SECRETS, separated by a space
# - Deploy github/github so the new token can be used for validation
# - Wait a while after the deploy
# - Swap the tokens in SPAMURAI_TIMESTAMP_SECRETS so the new token comes first.
# - Deploy github/github so the new token can be used for signing
# - Wait a while after the deploy
# - Clean up the old token from the string that's now at the end.

class SpamuraiFormSignals
  # The REQUIRED_KEYS constant is used in the hydro entity serializer where the incoming object keys
  # are sorted and compared to this array. Call sort here to ensure they are sorted the same.
  REQUIRED_KEYS = [:current_timestamp, :honeypot_failure, :timestamp, :timestamp_secret].sort
  REQUIRED_FIELD_REGEX = /\Arequired_field_\w{4}\z/

  def self.create(request_params:, current_timestamp: Timestamp.milliseconds_since_epoch)
    request_params = ActiveSupport::HashWithIndifferentAccess.new(request_params || {})
    honeypot_key = request_params.keys.find { |key| key =~ REQUIRED_FIELD_REGEX }
    honeypot_failure = honeypot_key.present? ? request_params[honeypot_key.to_sym].present? : true

    new(
      honeypot_failure: honeypot_failure,
      timestamp: request_params[:timestamp],
      timestamp_secret: request_params[:timestamp_secret],
      current_timestamp: current_timestamp,
    )
  end

  def initialize(honeypot_failure:, timestamp:, timestamp_secret:, current_timestamp:)
    @honeypot_failure = honeypot_failure
    @timestamp = timestamp
    @timestamp_secret = timestamp_secret
    @current_timestamp = current_timestamp
  end

  attr_reader :timestamp, :timestamp_secret

  def load_to_submit_in_milliseconds
    return unless timestamp.present? && timestamp_secret.present?
    return if load_to_submit_timestamp_hacked?

    @current_timestamp.to_i - timestamp.to_i
  end

  def load_to_submit_timestamp_hacked?
    return false unless GitHub.spamminess_check_enabled?
    return false unless timestamp.present? && timestamp_secret.present?

    GitHub.spamurai_timestamp_secrets.all? do |secret|
      !SecurityUtils.secure_compare(timestamp_secret, self.class.timestamp_hmac(timestamp, secret))
    end
  end

  def load_to_submit_timestamp_missing?
    timestamp.nil?
  end

  def load_to_submit_timestamp_secret_missing?
    timestamp_secret.nil?
  end

  def honeypot_failure?
    @honeypot_failure
  end

  # Public: Calculate timestamp HMAC for spamurai form signals.
  #
  # timestamp - Integer milliseconds since epoch.
  #
  # Returns a String.
  def self.timestamp_hmac(timestamp, secret = GitHub.spamurai_timestamp_secrets.first)
    OpenSSL::HMAC.hexdigest("sha256", secret, "#{timestamp}")
  end
end
