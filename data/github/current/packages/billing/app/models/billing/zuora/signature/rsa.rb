# typed: true
# frozen_string_literal: true

class Billing::Zuora::Signature::RSA

  # Generates a Zuora RSA signature object used in the generation of a
  # Zuora Hosted Payments Page
  #
  # uri - Zuora payment page endpoint
  # page_id - ID of the page that will be rendered
  #
  # Returns Billing::Zuora::Signature::RSA or nil
  def self.generate(uri:, page_id:, account_id: nil)
    rsa_params = {
      uri: uri,
      pageId: page_id,
      method: "POST",
    }
    rsa_params[:accountId] = account_id if account_id

    response = GitHub.zuorest_client.create_rsa_signature(rsa_params)

    new(
      key: response["key"],
      signature: response["signature"],
      tenant_id: response["tenantId"],
      token: response["token"],
    )
  rescue ::Faraday::TimeoutError
    GitHub.dogstats.increment("zuora.timeout_error")
    nil
  rescue ::Faraday::ConnectionFailed
    GitHub.dogstats.increment("zuora.connection_failed")
    nil
  end

  attr_reader :key, :signature, :tenant_id, :token

  def initialize(key: nil, signature: nil, tenant_id: nil, token: nil)
    @key = key
    @signature = signature
    @tenant_id = tenant_id
    @token = token
  end

  def public_encrypt(value)
    Base64.encode64(rsa_cipher.public_encrypt(value))
  end

  private

  def rsa_cipher
    @encrypter ||= OpenSSL::PKey::RSA.new("-----BEGIN PUBLIC KEY-----\n#{key}\n-----END PUBLIC KEY-----")
  end
end
