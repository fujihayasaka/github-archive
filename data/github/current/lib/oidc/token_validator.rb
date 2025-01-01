# typed: false
# frozen_string_literal: true

require "oidc"

module OIDC
  #
  # TokenValidator is responsible for validation of jwt tokens
  # A Result object will always be returned from validation.
  # Upon successful validation the Result.success? will return true, otherwise false
  #
  # Usage:
  #   result = OIDC::TokenValidator.validate_token(jwt, oidc_provider)
  #   claims = result.claims if result.success?
  #   headers = result.headers if result.success?
  #
  # result.error will contain the raised exception, and result.message the error message in the exception
  #
  class TokenValidator
    # Making the new methods private since the class is intended to be accessed through
    # validate_token method only
    private_class_method :new

    AZUREAD_REGEX = %r{sts\.windows\.net/(?<id>[a-z0-9\-]+)/}i
    OKTA_REGEX = %r{www\.okta\.com/(?<id>[a-z0-9]+)}i

    class TokenValidationError < StandardError; end
    class InvalidProviderConfiguration < TokenValidationError; end
    class InvalidSigningKeys < TokenValidationError; end
    class CHashDoesNotMatch < TokenValidationError; end

    class Result
      private_class_method :new

      attr_reader :claims, :headers, :error

      def initialize(claims: nil, headers: nil, error: nil)
        @claims  = claims
        @headers = headers
        @error   = error
      end

      def success?
        error.nil?
      end

      def message
        return nil unless error
        error.message
      end

      def self.success(claims, headers)
        new(claims: claims, headers: headers)
      end

      def self.failure(error)
        new(error: error)
      end
    end

    # Create the token validator based on a business oidc provider
    # tenant_provider - OIDC::TenantProvider
    def initialize(tenant_provider)
      @tenant_provider = tenant_provider
    end

    # Verifies the signature of the provided token
    # Also verifies the claims from verify_options including
    # expiration, not_before, issued_at, issuer, audience
    #
    # token - jwt token to verify and parse
    # tenant_provider - OIDC::TenantProvider the token was issued
    # verification_options - an override for verification options
    #
    # See OpenId Connect Core 3.1.3.7 and 3.2.2.11.
    #
    # Returns Result
    def self.validate_token(token, tenant_provider, code: nil, verification_options: nil)

      new(tenant_provider).validate_and_parse_token(token, code, verification_options)
    end

    # Verifies the signature of the provided token
    # Also verifies the claims from verify_options including
    # expiration, not_before, issued_at, issuer, audience
    # if setup true we want to skip issuer check
    #
    # See OpenId Connect Core 3.1.3.7 and 3.2.2.11.
    #
    # @return claims, header when valid
    #         raises an error when there is a parsing or validation error
    def validate_and_parse_token(token, code, verification_options)
      verification_options ||= verify_options
      # The second parameter is the public key to verify the signature.
      # However, that key is overridden by the value of the executed block
      # if one is present.
      jwt_claims, jwt_header =
        JWT.decode(token, nil, true, verification_options) do |header|
          public_key(header)
        end
      jwt_claims = jwt_claims.with_indifferent_access
      jwt_header = jwt_header.with_indifferent_access

      if code && !validate_chash(code, jwt_claims, jwt_header)
        raise CHashDoesNotMatch, "Authorization code and c_hash claim do not match"
      end

      Result.success(jwt_claims, jwt_header)

    rescue JWT::DecodeError, TokenValidationError,
           OIDC::TenantProvider::TenantProviderError => error
      Failbot.report!(error, business_id: @tenant_provider.business_id)

      Result.failure(error)
    end

    # Parses the token without any verifications
    #
    # @return claims, header when valid
    #         raises an error when there is a parsing or validation error
    def self.parse_token(token)
      new(nil).parse_token(token)
    end

    # Parses the token without any verifications
    #
    # @return claims, header when valid
    #
    def parse_token(token)
      jwt_claims, jwt_header = JWT.decode(token, nil, false)

      Result.success(jwt_claims.with_indifferent_access, jwt_header.with_indifferent_access)
    rescue JWT::DecodeError
      Failbot.report!(error)

      Result.failure(error)
    end

    def self.verify_idp_token_options(tenant_provider)
      {
        verify_expiration: true,
        verify_not_before: true,
        verify_iat: true,
        verify_iss: false,
        verify_aud: false,
        algorithms: tenant_provider.configuration.token_signing_alg_values,
      }
    end
    private_class_method :verify_idp_token_options

    def self.valid_idp_token?(token)
      result = parse_token(token)

      if result.claims.key?("iss") && result.claims.key?("tid") && result.claims.key?("appid")
        oidc_provider_key = nil

        case result.claims["iss"]
        when AZUREAD_REGEX
          oidc_provider_key = "azure"
        when OKTA_REGEX
          oidc_provider_key = "okta"
        else
          return false
        end

        tenant_provider = OIDC::TenantProvider.new(nil, oidc_provider_key: oidc_provider_key)
        result = new(tenant_provider).validate_and_parse_token(token, nil, verify_idp_token_options(tenant_provider))
        if result.success?
          return true
        end
      end
      false
    end


    private

    # Converts JSON Web Key parameters to an RSA public key.
    #
    # n - The modulus of the key.
    # e - The exponent of the key.
    #
    # Returns an OpenSSL::PKey::RSA public key.
    # Raises OpenSSL::PKey::RSAError if the key cannot be created.
    def jwks_to_public_key(n, e)
      # Sending 2 as the second argument to OpenSSL::BN.new since, when we decode the base64 encoded we get large binary numbers
      exponent = OpenSSL::BN.new(Base64.urlsafe_decode64(e), 2)
      modulus = OpenSSL::BN.new(Base64.urlsafe_decode64(n), 2)

      begin
        OpenSSL::PKey::RSA.new.tap do |key|
          # modulus, exponent, private_exponent
          key.set_key(modulus, exponent, nil)
        end
      rescue OpenSSL::PKey::PKeyError => e
        raise JWT::VerificationError, "Invalid key parameters: #{e.message}"
      end
    end

    # Returns the public key to decode the token
    #
    # header  -   a hash representing the token header
    #
    # @returns public key
    #          raises JWT::VerificationError if no signing key matches header


    def public_key(header, busted_cache = false)
      keys = signing_keys(busted_cache).signing_keys
      key_data = keys.find { |key| key["kid"] == header["kid"] } || {}

      # if key_data is empty, burst the cache and try again
      if key_data.empty? && !busted_cache
        return public_key(header, true)
      end

      # See https://github.com/github/actions-runtime/issues/4166#issuecomment-1830429707, tokenz currently doesn't return x5c
      # When https://github.com/github/actions-fusion/issues/812 is done, we can remove this check
      # We only attempt this if x5c is not present, so this logic currently only applies to tokenz tokens
      if key_data["n"] && key_data["e"] && !key_data["x5c"]
        jwks_to_public_key(key_data["n"], key_data["e"])
      else
        x5c = key_data["x5c"]
        if x5c.nil? || x5c.empty?
          raise JWT::VerificationError, "No keys from key endpoint match the id token"
        end

        # The AAD signing keys also contains other fields, such as n and e, that are
        # redundant. x5c is sufficient to verify the token.
        # x5c itself is an array so retrieve the first one.
        OpenSSL::X509::Certificate.new(url_decode(x5c.first)).public_key
      end
    end

    # Verifies that the c_hash the id token claims matches the authorization
    # code. See OpenId Connect Core 3.3.2.11.
    def validate_chash(code, claims, headers)
      # This maps RS256 -> sha256, ES384 -> sha384, etc.
      algorithm = (headers[:alg] || "RS256").sub(/RS|ES|HS/, "sha")
      full_hash = OpenSSL::Digest.new(algorithm).digest code
      c_hash = url_encode full_hash[0..full_hash.length / 2 - 1]
      SecurityUtils.secure_compare(c_hash, claims[:c_hash])
    end

    # The options passed to the Ruby JWT library to verify the token.
    # Nonce is handled elsewhere (TODO: fill in this spot when we have the proper class where this happens)
    #
    # @return Hash
    def verify_options
      {
        verify_expiration: true,
        verify_not_before: true,
        verify_iat: true,
        # When tenant_id is nil (provider was not setup yet)
        # we do not want to verify issuer, since the token is
        # going to be issued by the tenant and we do not have the tenant id yet.
        verify_iss: @tenant_provider.tenant_id.present?,
        verify_aud: true,
        algorithms: @tenant_provider.configuration.token_signing_alg_values,
        # We can leave the issuer, just turn off the verify_iss option
        iss: @tenant_provider.configuration.issuer,
        aud: @tenant_provider.client_id
      }
    end

    # Gets the current signing keys for the well-known OIDC provider
    # associated to the Business::OIDCProvider. Note that there should
    # always two available, and that they have a 6 week rollover.
    #
    # Each key is a hash with the following fields:
    #   kty, use, kid, x5t, n, e, x5c
    #
    # @return OIDC::Keys object
    def signing_keys(bust_cache = false)
      keys = OIDC::Cache.get_signing_keys(@tenant_provider.oidc_provider_key, @tenant_provider.configuration, bust_cache)
      raise InvalidSigningKeys, "Signing keys were not valid during token validation" unless keys.valid?
      keys
    end

    def url_decode(str)
      str += "=" * (4 - str.length.modulo(4))
      ::Base64.decode64(str.tr("-_", "+/"))
    end

    def url_encode(str)
      ::Base64.encode64(str).tr("+/", "-_").gsub(/[\n=]/, "")
    end
  end
end
