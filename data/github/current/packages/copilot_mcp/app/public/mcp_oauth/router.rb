# typed: strict
# frozen_string_literal: true

class McpOauth::Router
  class InvalidIssuerError < StandardError; end

  sig { returns(URI::HTTPS) }
  attr_reader :issuer_url

  sig { returns(String) }
  attr_reader :base_url

  sig { params(issuer_url: String).void }
  def initialize(issuer_url)
    parsed_url = URI(issuer_url)
    unless parsed_url.is_a?(URI::HTTPS)
      raise ArgumentError, "issuer_url must be a valid HTTPS URI"
    end
    @issuer_url = T.let(parsed_url, URI::HTTPS)
    @base_url = T.let("#{@issuer_url.scheme}://#{@issuer_url.host}", String)
    validate_issuer!
  end

  sig { void }
  def validate_issuer!
    unless issuer_url.scheme == "https" || issuer_url.host == "localhost"
      raise InvalidIssuerError, "Issuer URL must use HTTPS or be localhost for development"
    end

    raise InvalidIssuerError, "Issuer URL must not include a fragment" if issuer_url.fragment
    raise InvalidIssuerError, "Issuer URL must not include a query string" if issuer_url.query
  end

  sig { params(path: String).returns(String) }
  def url_for(path)
    URI.join(base_url.to_s, path).to_s
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def metadata
    McpOauth::BuildMetadata.call(base_url: base_url, fallback_router: self)
  end
end
