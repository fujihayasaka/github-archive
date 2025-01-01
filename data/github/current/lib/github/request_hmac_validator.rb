# typed: false
# frozen_string_literal: true

module GitHub
  class InvalidRequestHMAC < StandardError; end
  class MissingRequestHMACKeys < StandardError; end

  class RequestHmacValidator
    REQUEST_HMAC_INTERVAL = 10.minutes
    HMAC_ALGORITHM = "sha256"

    # Takes the HMAC of an integer epoch timestamp with key.
    def self.request_hmac(time, key)
      timestamp = time.to_i.to_s

      hmac = OpenSSL::HMAC.hexdigest(
        HMAC_ALGORITHM,
        key, timestamp
      )
      "#{timestamp}.#{hmac}"
    end

    def self.verify_request_hmac(received_hmac, request_hmac_keys)
      unless request_hmac_keys.present?
        err = MissingRequestHMACKeys.new "No Request-HMAC keys are set for #{self}"
        return status = :no_key
      end

      if received_hmac.blank?
        err = InvalidRequestHMAC.new "Request-HMAC header not present"
        return status = :empty_request_hmac
      end

      timestamp, hmac = received_hmac.split(".", 2)

      if timestamp.blank? || hmac.blank?
        err = InvalidRequestHMAC.new "Request-HMAC header missing either timestamp or hmac value"
        return status = :invalid_request_hmac
      end

      # We only need the integer value going forward.
      timestamp = timestamp.to_i

      # Allow for a bit of clock skew, latency, etc in either direction.
      valid_timestamp =
        timestamp > REQUEST_HMAC_INTERVAL.ago.to_i &&
        timestamp < REQUEST_HMAC_INTERVAL.from_now.to_i

      unless valid_timestamp
        err = InvalidRequestHMAC.new "Timestamp is outside the allowed range"
        return status = :invalid_timestamp
      end

      matching_key = request_hmac_keys.detect do |request_hmac_key|
        SecurityUtils.secure_compare(
          received_hmac,
          GitHub::RequestHmacValidator.request_hmac(Time.at(timestamp), request_hmac_key),
        )
      end
      status = matching_key ? :success : :fail
      [status, matching_key]
    ensure
      Failbot.report_user_error(err) if err
      GitHub.dogstats.increment("api.internal.request_hmac", tags: ["status:#{status}"])
    end

  end
end
