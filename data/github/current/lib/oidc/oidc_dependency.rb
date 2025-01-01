# typed: false
# frozen_string_literal: true

require "oidc"

module OIDCDependency
  CALLBACK_PATH = "/auth/oidc/callback"
  MULTI_TENANT_HOST = "https://auth"
  DEFAULT_SCOPE = "profile openid email offline_access"
  ACCESS_TOKEN_SCOPE = "openid offline_access"
  DEFAULT_RESPONSE_TYPE = "id_token code"
  DEFAULT_RESPONSE_MODE = "form_post"
  AUTH_CODE_GRANT_TYPE = "authorization_code"
  REFRESH_TOKEN_GRANT_TYPE = "refresh_token"
  CLIENT_ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"
  ERROR_DESCRIPTION = "error_description"
  REQUEST_TIMEOUT = "Request timed out"
  DEFAULT_TIMEOUT = 6 # default timeout in seconds
  PROMPT_SELECT_ACCOUNT = "select_account"

  # Create an authorize URL to call to a tenant provider
  # force_account_selection: if true, the IdP will prompt the user to select an account (important for account switcher)
  #                          without this, if the IdP has a single session, it will automatically use it
  #
  # Returns String
  def oidc_authorize_url(force_account_selection: false)
    business_tenant_provider = tenant_provider

    params = authorize_params(initiate_relay_state, business_tenant_provider)
    params[:prompt] = PROMPT_SELECT_ACCOUNT if force_account_selection

    query_parameters = params.keys.join(",")
    template = Addressable::Template.new("#{business_tenant_provider.configuration.authorization_endpoint}{?#{query_parameters}}")
    template.expand(params).to_s
  end

  # Create an token URL to call to a tenant provider
  #
  # Returns String
  def oidc_token_url(business)
    tenant_provider(business: business).configuration.token_endpoint
  end

  # Get the OIDC::TenantProvider associated to
  # the business. If we are in setup mode and there
  # is no Business::OIDCProvider for the business yet, we build a generic
  # tenant provider based on the setup key.
  #
  # Returns OIDC::TenantProvider
  def tenant_provider(business: nil, setup: nil)
    business ||= this_business

    setup ||= params[:oidc][:oidc_provider] if defined?(params) && params[:oidc].present? && params[:oidc][:oidc_provider].present?

    OIDC::TenantProvider.new(business, oidc_provider_key: setup)
  end

  # Private: Authorize url query parameters
  #
  # Returns Hash
  def authorize_params(relay_state, tenant_provider)
    if GitHub.multi_tenant_enterprise?
      {
        client_id: tenant_provider.client_id,
        redirect_uri: "#{MULTI_TENANT_HOST}.#{GitHub.host_name}#{CALLBACK_PATH}",
        response_mode: DEFAULT_RESPONSE_MODE,
        response_type: DEFAULT_RESPONSE_TYPE,
        nonce: relay_state.nonce,
        state: relay_state.request_id,
        tenant_id: tenant_provider.tenant_id,
        scope: DEFAULT_SCOPE,
      }
    else
      {
        client_id: tenant_provider.client_id,
        redirect_uri: GitHub.url + CALLBACK_PATH,
        response_mode: DEFAULT_RESPONSE_MODE,
        response_type: DEFAULT_RESPONSE_TYPE,
        nonce: relay_state.nonce,
        state: relay_state.request_id,
        tenant_id: tenant_provider.tenant_id,
        scope: DEFAULT_SCOPE,
      }
    end
  end

  # Private: Token url parameters for the interactive access_token/refresh_token request
  #
  # Returns Hash
  def authorization_code_token_params(client_id:, authorization_code:, token_url:, certificate:)
    return nil if certificate.nil?
    if GitHub.multi_tenant_enterprise?
      {
        client_id: client_id,
        grant_type: AUTH_CODE_GRANT_TYPE,
        code: authorization_code,
        redirect_uri: "#{MULTI_TENANT_HOST}.#{GitHub.host_name}#{CALLBACK_PATH}",
        client_assertion_type: CLIENT_ASSERTION_TYPE,
        client_assertion: client_assertion_jwt(token_url: token_url, certificate: certificate, client_id: client_id),
        scope: ACCESS_TOKEN_SCOPE,
      }
    else
      {
        client_id: client_id,
        grant_type: AUTH_CODE_GRANT_TYPE,
        code: authorization_code,
        redirect_uri: GitHub.url + CALLBACK_PATH,
        client_assertion_type: CLIENT_ASSERTION_TYPE,
        client_assertion: client_assertion_jwt(token_url: token_url, certificate: certificate, client_id: client_id),
        scope: ACCESS_TOKEN_SCOPE,
      }
    end
  end

  # Private: Token url parameters for the interactive access_token/refresh_token request
  #
  # Returns Hash
  def refresh_token_params(client_id:, refresh_token:, token_url:, client_ip:, certificate:)
    return nil if certificate.nil?
    if GitHub.multi_tenant_enterprise?
      {
        client_id: client_id,
        grant_type: REFRESH_TOKEN_GRANT_TYPE,
        refresh_token: refresh_token,
        redirect_uri: "#{MULTI_TENANT_HOST}.#{GitHub.host_name}#{CALLBACK_PATH}",
        client_assertion_type: CLIENT_ASSERTION_TYPE,
        client_assertion: client_assertion_jwt(token_url: token_url, certificate: certificate, client_id: client_id, client_ip: client_ip)
      }
    else
      {
        client_id: client_id,
        grant_type: REFRESH_TOKEN_GRANT_TYPE,
        refresh_token: refresh_token,
        redirect_uri: GitHub.url + CALLBACK_PATH,
        client_assertion_type: CLIENT_ASSERTION_TYPE,
        client_assertion: client_assertion_jwt(token_url: token_url, certificate: certificate, client_id: client_id, client_ip: client_ip)
      }
    end
  end

  def client_assertion_jwt(token_url:, client_id:, certificate:, client_ip: nil)
    p12 = OpenSSL::PKCS12.new(certificate)

    payload = {
      aud: token_url,
      exp: (Time.now + 10.minutes).to_i,
      nbf: (Time.now - 1.minute).to_i,
      sub: client_id,
      jti:  SecureRandom.uuid,
      iss: client_id,
      client_ip: client_ip
    }.compact

    # RFC 7515 4.1.7 recommends use of SHA1 for the certificate fingerprint used for x5t.
    hash = OpenSSL::Digest::SHA1.digest(p12.certificate.to_der) # rubocop:disable GitHub/InsecureHashAlgorithm
    x5t = Base64.urlsafe_encode64(hash).strip
    JWT.encode payload, p12.key, "RS256", { typ: "JWT", x5t: x5t }
  end

  def authorization_code_access_token_request(business:, authorization_code:)
    token_url = oidc_token_url(business)
    client_id = tenant_provider(business: business).client_id

    business ||= this_business
    if business.feature_flag_enabled?(:oidc_force_previous_cert, default: false)
      previous_token_params = authorization_code_token_params(
        client_id: client_id,
        authorization_code: authorization_code,
        token_url: token_url,
        certificate: OIDC::Certificate.previous,
      )
      res = get_access_token_with_retry(business, token_url: token_url, token_params: previous_token_params)
    else
      current_token_params = authorization_code_token_params(
        client_id: client_id,
        authorization_code: authorization_code,
        token_url: token_url,
        certificate: OIDC::Certificate.current,
      )
      res = get_access_token_with_retry(business, token_url: token_url, token_params: current_token_params)
    end

    log_access_token_response(res: res, cap: false, business: business)
  end

  def refresh_token_access_token_request(business:, refresh_token:, client_ip:)
    token_url = oidc_token_url(business)
    client_id = tenant_provider(business: business).client_id

    business ||= this_business
    if business.feature_flag_enabled?(:oidc_force_previous_cert, default: false)
      previous_token_params = refresh_token_params(
        client_id: client_id,
        refresh_token: refresh_token,
        token_url: token_url,
        client_ip: client_ip,
        certificate: OIDC::Certificate.previous,
      )
      res = get_access_token_with_retry(business, token_url: token_url, token_params: previous_token_params)
    else
      current_token_params = refresh_token_params(
        client_id: client_id,
        refresh_token: refresh_token,
        token_url: token_url,
        client_ip: client_ip,
        certificate: OIDC::Certificate.current,
      )
      res = get_access_token_with_retry(business, token_url: token_url, token_params: current_token_params)
    end

    log_access_token_response(res: res, cap: true, business: business)
  end

  # Private: Get access token with retry.  The method will only retry once if the first request times out, however
  #   the timeout for the second retry will be half of the original timeout, since the unicorn timeout is 10 seconds.
  #
  # Returns Faraday::Response
  def get_access_token_with_retry(business, token_url:, token_params:, retries: 1, timeout: DEFAULT_TIMEOUT)
    validate_token_url(token_url)

    res = begin
      Faraday.post(token_url, token_params) do |request|
        request.options.timeout = timeout / retries # open/read timeout in seconds
      end
    rescue Faraday::TimeoutError
      Faraday::Response.new(status: 408, body: { ERROR_DESCRIPTION => REQUEST_TIMEOUT }.to_json)
    rescue Faraday::ConnectionFailed => e
      Faraday::Response.new(status: 502, body: { ERROR_DESCRIPTION => e.message }.to_json)
    end

    if res.success? || retries >= 2
      res
    else
      get_access_token_with_retry(business, token_url: token_url, token_params: token_params, retries: retries + 1)
    end
  end

  def log_access_token_response(res:, cap:, business:)
    cert_result = if res.success?
      "success"
    else
      "failure"
    end
    current_cert = if business.feature_flag_enabled?(:oidc_force_previous_cert, default: false) # long-lived FF
      false
    else
      true
    end

    GitHub.logger.info(
      "OIDC certificate usage",
      "code.function" => __method__,
      "gh.request.id" => GitHub.context[:request_id],
      "gh.business.name" => business.slug,
      "gh.external_identities.current_cert" => current_cert,
      "gh.external_identities.cert_result" => cert_result,
      "gh.external_identities.cap_validation" => cap,
    )

    GitHub.dogstats.increment("external_identities.oidc_cert_usage", tags: ["status:#{cert_result}", "current_cert:#{current_cert}", "cap_validation:#{cap}"])

    res
  end

  def initiate_relay_state
    # using an `_` since it does not get encoded and `:` does
    request_id = "#{SecureRandom.uuid}_#{this_business.slug}"

    data = {
      business_id: this_business.id
    }

    data[:return_to] ||= params[:return_to] if params[:return_to].present?

    # params[:oidc][:oidc_provider] should be :azure, :okta for use in OIDCAuth tenant_provider
    data[:setup] = params[:oidc][:oidc_provider] if params[:oidc].present? && params[:oidc][:oidc_provider].present?
    # params[:oidc][:migrate] is used to migrate EMU provider from SAML to an OIDC provider
    data[:migrate_to_oidc] = params[:oidc][:migrate_to_oidc] if params[:oidc].present? && params[:oidc][:migrate_to_oidc].present?

    # Persist captured form data from enforced request so user
    # can replay it after SSO.
    data[:form_data] = params[:form_data] if params[:form_data]

    if credential_authorization_request.presence
      data.update credential_authorization_request_params_for(credential_authorization_request) || Hash.new
    end

    relay_state = OIDC::RelayState.initiate(
      request_id: request_id,
      data: data,
    )

    # persist the relay state digest for future validation
    # Cookie attributes are additionally set by by app/controller/application_controller/security_headers_dependency.rb
    # By default the :oidc_csrf_token will have the SameSite=none attribute set from the secure_headers gem.
    # The :oidc_csrf_legacy cookie does not have the SameSite=none attribute set. This is to accomodate
    # browsers that reject or mistreat cookies with the SameSite=none attribute. In particular, there is
    # a bug that treats SameSite=None and invalid values as Strict in macOS before 10.15 Catalina and in iOS before 13.
    cookies.encrypted[:oidc_csrf_token] = oidc_csrf_cookie(relay_state.digest)
    cookies.encrypted[:oidc_csrf_token_legacy] = oidc_csrf_cookie(relay_state.digest)

    relay_state
  end

  # For tagging metrics
  def authed_or_anon
    logged_in? ? "auth" : "anon"
  end

  def record_sso_initiated
    GitHub.dogstats.increment "oidc.sso_initiated",
      tags: dogstats_request_tags + [
        "logged_in:#{authed_or_anon}",
        "return_to:#{params[:return_to].present?}",
        "authorization_request:#{params[:authorization_request].present?}",
      ]
  end

  # Encrypted cookies have some odd behavior when the exact same object is used as a value
  # This reduces repetition while helping create valid cookies.
  def oidc_csrf_cookie(digest)
    {
      value: digest,
      expires: ::RelayState::DEFAULT_EXPIRY,
      secure: request && request.ssl?,
      httponly: true,
      domain: cookie_domain,
    }
  end

  def credential_authorization_request
    return unless token = params[:authorization_request].presence

    Organization::CredentialAuthorization.consume_request(
      target: this_business,
      token: token,
      actor: current_user,
    )
  end

  def credential_authorization_request_params_for(request)
    return unless request.present?

    organization_id = request.data["organization_id"]
    credential_type = request.data["credential_type"]
    credential_id   = request.data["credential_id"]

    return unless organization_id && credential_type && credential_id

    organization = Organization.find_by(id: organization_id)

    return unless organization.present?

    credential = OauthAccessTokens.domain.by_user_and_id(current_user.id, credential_id) if credential_type == "OauthAccess"
    credential = current_user.public_keys.find_by_id(credential_id) if credential_type == "PublicKey"

    return unless credential.present?
    {
      organization_id: organization.id,
      credential_id: credential.id,
      credential_type: credential.class.name,
      fingerprint: credential.fingerprint
    }
  end

  private

  def validate_token_url(token_url)
    allowed_hosts = ["login.microsoftonline.com"]
    uri = URI.parse(token_url)
    unless allowed_hosts.include?(uri.host)
      raise "Invalid token URL"
    end
  end
end
