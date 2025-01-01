# typed: true
# frozen_string_literal: true

class FetchOcspJob < ApplicationJob
  queue_as GitSigning::QUEUE
  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  # Use OCSP to check if any certificates in a chain have been revoked.
  #
  # b64_subject   - An OpenSSL::X509::Certificate in base64 format.
  # b64_issuer    - An OpenSSL::X509::Certificate in base64 format.
  # b64_untrusted - OpenSSL::X509::Certificates in base64 format.
  def perform(b64_subject, b64_issuer, *b64_untrusted)
    subject = decode_cert(b64_subject)
    issuer  = decode_cert(b64_issuer)
    untrusted = b64_untrusted.map { |u| decode_cert(u) }

    ApplicationRecord::Domain::KeyValues.throttle_writes do
      GitHub::OCSP.check_sync(subject, issuer, untrusted)
    end
  end

  def decode_cert(b64)
    OpenSSL::X509::Certificate.new(Base64.decode64(b64))
  end
end
