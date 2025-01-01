# typed: strict
# frozen_string_literal: true

module GitHub
  class InvalidAssetHMAC < StandardError; end
  class MissingAssetHMACKeys < StandardError; end

  # Validates the HMAC of an asset's SHA256 digest against a shared secret key.
  # The HMAC is computed over the following string: `<asset_key>:<sha256-asset-digest>`.
  #
  # The SHA256 digest and HMAC are received as request headers from memory-alpha. The
  # asset key is the value used in the upload policy form provided to memory-alpha.
  class AssetDigestHmacValidator
    HMAC_ALGORITHM = "sha256"

    sig { params(asset_key: String, digest: String, hmac: String).returns(T::Boolean) }
    def self.verify_digest_hmac(asset_key, digest, hmac)
      err = nil

      if asset_key.blank?
        err = InvalidAssetHMAC.new("Asset key is missing")
        return false
      end

      if digest.blank? || hmac.blank?
        err = InvalidAssetHMAC.new("Asset digest or HMAC request headers missing")
        return false
      end

      message = "#{asset_key}:#{digest}"

      # Get secret key shared with memory-alpha (two keys to support key rotation)
      secret_keys = [
        GitHub.memory_alpha_sha256_digest_hmac_key,
        GitHub.memory_alpha_sha256_digest_secondary_hmac_key
      ].reject(&:blank?)

      if secret_keys.empty?
        err = MissingAssetHMACKeys.new("No Asset Digest HMAC keys are set for #{self}")
      end

      valid = secret_keys.any? do |secret_key|
        # Compute expected HMAC
        expected_hmac = OpenSSL::HMAC.hexdigest(HMAC_ALGORITHM, secret_key, message)
        ActiveSupport::SecurityUtils.secure_compare(expected_hmac, hmac)
      end
    ensure
      Failbot.report_user_error(err) if err
      GitHub.dogstats.increment("release_asset.digest.invalid_hmac") unless valid
    end
  end
end
