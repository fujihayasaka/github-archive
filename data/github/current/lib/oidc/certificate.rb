# typed: true
# frozen_string_literal: true

module OIDC
  class Certificate
    def self.current
      decode_base64_cert(GitHub.oidc_azure_ad_client_certificate_current_encoded, true)
    end

    def self.previous
      decode_base64_cert(GitHub.oidc_azure_ad_client_certificate_previous_encoded, false)
    end

    private_class_method def self.decode_base64_cert(cert, current)
      return unless cert
      begin
        decoded_cert = Base64.decode64(cert)
        GitHub.dogstats.increment("external_identities.oidc_cert_decode", tags: ["status:success", "current_cert:#{current}"])
        decoded_cert
      rescue => e
        # Catch the error and report it to failbot
        msg = "Cannot decode the #{current ? "current" : "previous"} OIDC certificate: #{e.message}"
        GitHub.dogstats.increment("external_identities.oidc_cert_decode", tags: ["status:failure", "current_cert:#{current}"])
        Failbot.report!(
          e,
          error_messages: msg,
          current_certificate: current,
        )
        nil
      end
    end
  end
end
