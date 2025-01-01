# typed: true
# frozen_string_literal: true

class SamlEncryptedAssertions

  # The certifcates are valid for 10 years
  DEFAULT_CERT_VALIDITY = 10 * 365 * 24 * 60 * 60

  def self.create_cert(key, ou, cn, email)
    entity = [
      ["C",  "US",            OpenSSL::ASN1::PRINTABLESTRING],
      ["ST", "California",    OpenSSL::ASN1::PRINTABLESTRING],
      ["L",  "San Francisco", OpenSSL::ASN1::PRINTABLESTRING],
      ["O",  "GitHub, Inc.",  OpenSSL::ASN1::UTF8STRING],
      ["OU", ou,              OpenSSL::ASN1::UTF8STRING],
      ["CN", cn,              OpenSSL::ASN1::UTF8STRING]
    ]
    entity << ["emailAddress", email, OpenSSL::ASN1::UTF8STRING] if email

    # Create certificate signing request
    request = OpenSSL::X509::Request.new
    request.version = 0
    request.subject = OpenSSL::X509::Name.new(entity)
    request.public_key = key.public_key
    request.sign(key, OpenSSL::Digest::SHA256.new)

    # Sign certificate request
    csr_cert = OpenSSL::X509::Certificate.new
    csr_cert.serial = 0
    csr_cert.version = 2
    csr_cert.not_before = Time.now
    csr_cert.not_after = Time.now + DEFAULT_CERT_VALIDITY
    csr_cert.subject = request.subject
    csr_cert.public_key = request.public_key
    csr_cert.issuer = OpenSSL::X509::Name.parse("CN=github.com")
    csr_cert.sign(key, OpenSSL::Digest::SHA256.new)

    csr_cert.to_pem
  end
end
