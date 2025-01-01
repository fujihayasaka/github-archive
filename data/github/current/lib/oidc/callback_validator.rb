# typed: false
# frozen_string_literal: true

module OIDC
  # CallbackValidator is responsible for validation of id_token, business, and relay_state
  # when the callback endpoint is posted to from an IdP.
  # A Result object will always be returned from the validation.
  # Upon successful validation the Result.success? will return true, otherwise false
  #
  # Usage:
  #   result = validate_params
  #   claims = result.claims if result.success?
  #   headers = result.headers if result.success?
  #
  # result.error will contain the raised exception, and result.message the error message in the exception
  #
  module CallbackValidator
    # Result object returned from a callback method validation
    class Result
      private_class_method :new

      attr_reader :relay_state, :business, :claims, :external_id, :login, :at, :authorization_code, :sso_error, :error_message

      def initialize(relay_state: nil, business: nil, claims: nil, external_id: nil, login: nil, at: nil,
                     authorization_code: nil, sso_error: nil, error_message: nil)
        @relay_state  = relay_state
        @business     = business
        @claims       = claims

        @external_id  = external_id
        @login        = login

        @authorization_code = authorization_code

        @at            = at
        @sso_error     = sso_error
        @error_message = error_message
      end

      def success?
        sso_error.nil?
      end

      def self.success(relay_state, business, claims, authorization_code)
        new(relay_state: relay_state, business: business, claims: claims, authorization_code: authorization_code)
      end

      def self.failure(error, error_message)
        new(at: INVALID_AT, sso_error: error, error_message: error_message)
      end

      def self.invalid_relay_state(external_id, user)
        new(external_id: external_id, login: user&.login, at: RELAYSTATE_AT, sso_error: :invalid, error_message: INVALID_MESSAGE)
      end

      def self.invalid_business(external_id, user)
        new(external_id: external_id, login: user&.login, at: UNAUTHORIZED_AT, sso_error: :invalid_business, error_message: UNAUTHORIZED_MESSAGE)
      end
    end

    ERROR_DESCRIPTION = "error_description"
    ERROR_REASON = "error_reason"
    ERROR = "error"
    STATE = "state"
    ID_TOKEN = "id_token"
    CODE = "code"
    SESSION_STATE = "session_state"

    INVALID_AT = "failure - Invalid OIDC response"
    INVALID_MESSAGE = "Unable to authenticate your OIDC session.  Please try again or contact an administrator of your enterprise."

    UNAUTHORIZED_AT = "failure - Unauthorized"
    UNAUTHORIZED_MESSAGE = "Unsuccessful OIDC authorization, no access to the enterprise.  Please contact an administrator of your enterprise."

    REFRESHTOKEN_AT = "failure - Invalid response from IDP"
    REFRESHTOKEN_MESSAGE = "Unsuccessful OIDC authorization, invalid response from IDP.  Please try again later."

    RELAYSTATE_AT = "failure - Invalid relay state"

    OIDC_PARAMETERS_ERROR = "Required OIDC parameters were not supplied"

    # Verifies the signature of the provided token
    # Also verifies the claims from verify_options including
    # expiration, not_before, issued_at, issuer, audience
    #
    # request_params - request parameters to validate
    # tenant_provider - OIDC::TenantProvider the token was issued
    # verification_options - an override for verification options
    #
    # Returns Result
    def validate_params
      # Check if the request returned an error
      error = request.params[ERROR_REASON] || request.params[ERROR] || request.params[ERROR_DESCRIPTION]
      return OIDC::CallbackValidator::Result.failure(error, request.params[ERROR_DESCRIPTION] || error) if error

      # Get the parameters from the request, the request_id will be returned in
      # the state parameter, id_token and code are validated later.
      request_id = request.params[STATE]
      id_token = request.params[ID_TOKEN]
      authorization_code = request.params[CODE]

      # All three parameter must be supplied
      return OIDC::CallbackValidator::Result.failure(:invalid_parameters, OIDC_PARAMETERS_ERROR) unless request_id && id_token && authorization_code

      # Parse the JWT token to get claims, the token is not validated at that time
      # since there is no business yet to validate provider type.  However, we need a
      # nonce which is passed back as part of the claims to consume the relay_state.
      # Once the relay_state is consumed and validated we con obtain a business and
      # later validate token.
      result = OIDC::TokenValidator.parse_token(id_token)
      return OIDC::CallbackValidator::Result.failure(result.error.class, result.message) unless result.success?

      oid = result.claims[:oid]

      # relay_state is set during the initialize phase of an OIDC call
      # it is consumed here and it must match the request_id (session_state) and nonce
      # in the claims.  It also depends on the digest stored in the oidc_csrf_token cookies
      # which are also initially set when the relay_state is created.
      relay_state = consume_relay_state(request_id, result.claims[:nonce])
      return OIDC::CallbackValidator::Result.invalid_relay_state(oid, current_user) if relay_state.nil? || relay_state.invalid?
      return OIDC::CallbackValidator::Result.invalid_relay_state(oid, current_user) unless relay_state.data.present?

      # business needs to be validated for all sso call with exception of setup
      # if this is a setup call we need to brach off and
      # update the provider tenant id which will be found in the claims
      # no user validation is required for setup, since no users will be
      # provisioned yet
      business = validate_business(result.claims[:tid], relay_state)
      return OIDC::CallbackValidator::Result.invalid_business(oid, current_user) if business.nil?

      # Fully validate a token (signature, audience, dates and issuer), the issuer might have to be skipped
      # for setup, since there is no tenant attached yet to a business and we are trying to get the
      # tenant out of the claims.  The issuer will have the tenant id in the claim, since the token was issued by
      # the tenant that the user signed in with.  This is also the validation of the authorization code that was received
      # with the id token.  The code is encoded in the claims as c_hash and is
      # using the algorithm passed in the header.
      result = OIDC::TokenValidator.validate_token(
        id_token,
        tenant_provider(business: business, setup: relay_state.data["setup"]),
        code: authorization_code
      )
      return OIDC::CallbackValidator::Result.failure(result.error.class, result.message) unless result.success?

      # For setup user needs to be signed in and business needs to be adminable by a user
      if setup_provider_settings?(relay_state)
        return OIDC::CallbackValidator::Result.invalid_business(oid, current_user) unless logged_in? || business.adminable_by?(current_user)
      end

      OIDC::CallbackValidator::Result.success(relay_state, business, result.claims, authorization_code)
    end
  end
end
