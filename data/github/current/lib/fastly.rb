# typed: true
# frozen_string_literal: true

class Fastly
  extend T::Sig

  autoload :Certificate, "fastly/certificate"

  FASTLY_API_URL = "https://api.fastly.com".freeze
  FASTLY_CUSTOMER_ID = "5bPJi8MvwBUzRTFXlk5WhX".freeze
  FASTLY_PAGES_ID = "1XsGfPrccA8HNp9pTJebLx".freeze

  class Error < RuntimeError
  end

  class ValidationError < Error
  end

  class CertificateUploadError < Error
    attr_accessor :response
  end

  class CertificateFetchError < Error
    attr_accessor :response
  end

  class CertificateDeletionError < Error
    attr_accessor :response
  end

  class CDNPurgeError < Error
    attr_accessor :response
  end

  class FetchServiceError < Error
    attr_accessor :response
  end

  # Create a new Fastly client.
  #
  # options - Hash of options passed to Faraday.new.
  #
  # Returns nothing.
  def initialize(options = {})
    default_headers = {
      "Fastly-Key"   => GitHub.fastly_api_token,
      "Content-Type" => "application/json",
      "Accept"       => "application/json",
    }
    default_options = {
      url: FASTLY_API_URL,
      headers: default_headers,
      request: { timeout: 10, open_timeout: 5 },
    }
    @connection = Faraday.new(default_options[:url], default_options.merge(options)) do |f|
      f.adapter Faraday.default_adapter
    end
  end

  # Update a certificate. This modifies the certificate & certificate intermediate.
  # Useful for renewing a certificate.
  #
  # certificate - a Fastly::Certificate with the certificate_id, key_file, certificate, and certificate_intermediate fields.
  #
  # Returns a Fastly::Certificate from the response body JSON,
  # or raises a Fastly::CertificateUploadError if an unacceptable response is returned.
  def update_certificate(certificate)
    raise ValidationError, "Certificate ID is required" if certificate.certificate_id.to_s.empty?
    raise ValidationError, "Certificate is required" if certificate.certificate.to_s.empty?
    raise ValidationError, "Certificate intermediate is required" if certificate.certificate_intermediate.to_s.empty?
    raise ValidationError, "Key file is required" if certificate.key_file.to_s.empty?

    response = @connection.put do |req|
      req.url "/tls/#{FASTLY_CUSTOMER_ID}/certificate/#{certificate.certificate_id}"
      req.body = certificate.to_json
    end

    GitHub.dogstats.increment("pages.certificates.fastly_request", tags: ["status:#{response.status}", "method:update_certificate"])
    GitHub.dogstats.increment("pages.certificates.fastly_privkey_id", tags: [
      "fastly_private_key_id:#{certificate.key_file}", "method:update_certificate"
    ])

    if response.status > 201
      e = CertificateUploadError.new("invalid response code: #{response.status}").tap do |err|
        err.response = response
      end
      raise e
    end

    Fastly::Certificate.from_json(response.body)
  end

  # Upload a certificate to Fastly. This should only be called once per certificate.
  # For all renewals, use #update_certificate instead.
  #
  # certificate - a Fastly::Certificate with the certificate, certificate_intermediate, and key_file fields.
  #
  # Returns a Fastly::Certificate from the response body JSON,
  # or raises a Fastly::CertificateUploadError if an unacceptable response is returned.
  def upload_certificate(certificate)
    raise ValidationError, "Certificate is required" if certificate.certificate.to_s.empty?
    raise ValidationError, "Certificate intermediate is required" if certificate.certificate_intermediate.to_s.empty?
    raise ValidationError, "Key file is required" if certificate.key_file.to_s.empty?

    response = @connection.post do |req|
      req.url "/tls/#{FASTLY_CUSTOMER_ID}/certificate"
      req.body = certificate.to_json
    end

    GitHub.dogstats.increment("pages.certificates.fastly_request", tags: ["status:#{response.status}", "method:upload_certificate"])
    GitHub.dogstats.increment("pages.certificates.fastly_privkey_id", tags: [
      "fastly_private_key_id:#{certificate.key_file}", "method:upload_certificate"
    ])

    if response.status > 201
      e = CertificateUploadError.new("invalid response code: #{response.status}").tap do |err|
        err.response = response
      end
      raise e
    end

    Fastly::Certificate.from_json(response.body)
  end

  # Fetches a certificate's information from Fastly.
  #
  # certificate_id - a Fastly certificate ID
  #
  # Returns a Fastly::Certificate from the response body JSON,
  # or raises a Fastly::CertificateFetchError if an unacceptable response is returned.
  def get_certificate(certificate_id:)
    raise ValidationError, "Certificate ID is required" if certificate_id.to_s.empty?

    response = @connection.get do |req|
      req.url "/tls/#{FASTLY_CUSTOMER_ID}/certificate/#{certificate_id}"
    end

    GitHub.dogstats.increment("pages.certificates.fastly_request", tags: ["status:#{response.status}", "method:get_certificate"])

    if response.status != 200
      e = CertificateFetchError.new("invalid response code: #{response.status}").tap do |err|
        err.response = response
      end
      raise e
    end

    Fastly::Certificate.from_json(response.body)
  end

  # Deletes a certificate from Fastly.
  #
  # certificate_id - a Fastly Certificate ID
  #
  # Returns true if successful, or errors if not.
  def delete_certificate(certificate_id:)
    raise ValidationError, "Certificate ID is required" if certificate_id.to_s.empty?

    response = @connection.delete do |req|
      req.url "/tls/#{FASTLY_CUSTOMER_ID}/certificate/#{certificate_id}"
    end

    GitHub.dogstats.increment("pages.certificates.fastly_request", tags: ["status:#{response.status}", "method:delete_certificate"])

    if response.status != 200 && response.status != 404
      e = CertificateDeletionError.new("invalid response code: #{response.status}").tap do |err|
        err.response = response
      end
      raise e
    end
    true
  end

  # purge pages fastly CDN
  def purge_cdn(key)
    raise ValidationError, "purge key is required, otherwise it may purge all sites" if key.empty?
    response = @connection.post do |req|
      req.url "/service/#{FASTLY_PAGES_ID}/purge/#{key}"
    end

    GitHub.dogstats.increment("pages.certificates.fastly_request", tags: ["status:#{response.status}", "method:purge_cdn"])

    if response.status > 201
      e = CDNPurgeError.new("invalid response code: #{response.status}").tap do |err|
        err.response = response
      end
      raise e
    end
    true
  end

  # Public: Get the Fastly service ID for a given service name.
  sig { params(service_name: String).returns(String) }
  def service_id_for!(service_name)
    response = @connection.get do |req|
      req.url "/service/search"
      req.params[:name] = service_name
    end

    if response.status == 200
      JSON.parse(response.body)["id"]
    else
      error = FetchServiceError.new("invalid response code: #{response.status}").tap do |err|
        err.response = response
      end
      raise error
    end
  end

  # Public: Purges a specific URL from Fastly's cache.
  sig { params(url: String).returns(T::Boolean) }
  def purge!(url:)
    purgable_url = Addressable::URI.parse(url).to_s
    raise ValidationError, "URL must be present" if purgable_url.blank?

    response = @connection.post do |req|
      req.url "/purge/#{purgable_url}"
    end

    return true if response.status == 200

    error = CDNPurgeError.new("invalid response code: #{response.status}").tap do |err|
      err.response = response
    end
    raise error
  rescue Addressable::URI::InvalidURIError
    raise ValidationError, "valid URL is required"
  end

  # Public: Purges the entire Fastly cache for a service.
  sig { params(service_id: String).returns(T::Boolean) }
  def purge_all!(service_id:)
    response = @connection.post do |req|
      req.url "/service/#{service_id}/purge_all"
    end

    return true if response.status == 200

    error = CDNPurgeError.new("invalid response code: #{response.status}").tap do |err|
      err.response = response
    end
    raise error
  end

  # Utility method for talking to the Fastly API using authenticated @connection
  # Used mainly from one-off scripts or gh-console
  #
  # Usage Example to list private keys:
  # ```rb
  # list_private_key_options = {
  #   method: "get",
  #   url: "private_keys"
  # }
  # GitHub.fastly.request(request_options: list_private_key_options)
  # ```
  # Usage Example to add a new private key:
  # ```rb
  #   request_body = {
  #     "data": {
  #         "type": "tls_private_key",
  #             "attributes": {
  #             "key": "-----BEGIN PRIVATE KEY-----\n<key-data>\n-----END PRIVATE KEY-----\n",
  #             "name": "My private key" # This is the name we will reference in `github/github`
  #         }
  #     }
  #   }
  #
  #   create_private_key_options = {
  #       method: "post",
  #       url: "/tls/private_keys",
  #       body: request_body
  #   }
  #
  #   GitHub.fastly.request(request_options: create_private_key_options)
  # ```
  def request(request_options:)
    response = {}

    case request_options[:method]
    when "get"
      response = @connection.get do |req|
        req.url request_options[:url]
      end
    when "post"
      response = @connection.post do |req|
        req.url request_options[:url]
        req.body = request_options[:body].to_json
      end
    when "delete"
      response = @connection.delete do |req|
        req.url request_options[:url]
      end
    end

    response
  end

end
