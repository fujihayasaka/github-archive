# typed: true
# frozen_string_literal: true

class OauthExchangesController < ApplicationController
  # urn values defined in RFC 8693 (OAuth 2.0 Token Exchange):
  # https://datatracker.ietf.org/doc/html/rfc8693
  ISSUED_TOKEN_TYPE = T.let("urn:ietf:params:oauth:token-type:access_token", String)

  # First-party Microsoft Entra application ID for Visual Studio Code, the
  # only client whose subject tokens this endpoint accepts. Microsoft Entra
  # issues this value in the `azp` (v2.0) or `appid` (v1.0) claim.
  ENTRA_APPLICATION_ID = T.let("aebc6443-996d-45c2-90f0-388ff96faa56", String)

  GRANT_TYPE = T.let("urn:ietf:params:oauth:grant-type:token-exchange", String)
  SUBJECT_TOKEN_TYPE = T.let("urn:ietf:params:oauth:token-type:access_token", String)
  REQUIRED_PARAMS = T.let(%i[grant_type subject_token_type subject_token client_id client_secret].freeze, T::Array[Symbol])

  # The inherited CAP callback runs before the subject token is verified.
  # Re-register it after the token's business can be used as RFCA.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  before_action :ensure_endpoint_feature_enabled
  before_action :set_no_store_cache_headers
  before_action :require_url_form_encoded_form

  before_action :validate_required_params
  before_action :validate_grant_type
  before_action :validate_subject_token_type
  before_action :verify_subject_token
  before_action :ensure_business_in_feature_flag
  before_action :set_current_tenant
  before_action :resolve_emu_user
  before_action :validate_subject_token_authorized_party
  before_action :resolve_application
  before_action :validate_client_authentication
  before_action :authorize_client_for_grant_type

  before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  skip_after_action :block_non_xhr_json_responses

  def create
    application = resolved_application
    scopes = OauthAccessTokens::Domain.normalize_scopes(params[:scope]).join(",")

    result = OauthAccessTokens.domain.grant(
      user: resolved_emu_user,
      application: application,
      scope: scopes
    )

    unless result.is_a?(GH::Result::Ok)
      return render_oauth_error(error: :invalid_grant, error_description: "Token exchange failed")
    end

    # OauthAccessTokens.domain.grant always populates token_record with an
    # OauthAccess. The CreateResult type uses the IOauthAccess interface to
    # avoid cross-package coupling; cast to the concrete class so downstream
    # callers (e.g. OauthAccessTokenRequest) can rely on its full API.
    access = T.cast(result.value.token_record, OauthAccess)

    response = OauthAccessTokenRequest.process(
      application,
      log_data,
      {
        grant_type: OauthAccessTokenRequest::TOKEN_EXCHANGE_GRANT_TYPE,
        access:     access,
      },
      entry_point: :oauth_exchange_controller,
    )

    if response[:error]
      return render_oauth_error(**response.slice(:error, :error_description, :error_uri))
    end

    grant_authorized_org_credential_authorizations(credential: access, actor: resolved_emu_user)

    render json: response.merge(issued_token_type: ISSUED_TOKEN_TYPE), status: :ok
  end

  # Public: Override the inherited ApplicationController accessor so this endpoint
  # never falls back to session or cookie authentication. The actor is the EMU user
  # resolved from the verified Entra subject token, or no one.
  #
  # Must remain public because GlobalNavigationHelper declares `current_user` as a
  # public abstract method and Sorbet rejects narrowing visibility on override.
  #
  # Returns the resolved User or nil.
  def current_user # rubocop:disable GitHub/UseRestfulActions
    @resolved_emu_user
  end

  private

  def ensure_endpoint_feature_enabled
    return if FeatureFlag.vexi.enabled?(:entra_token_exchange_endpoint, default: false)

    render_404
  end

  def set_no_store_cache_headers
    response.headers["cache-control"] = "no-store"
    response.headers["pragma"] = "no-cache"
  end

  def require_url_form_encoded_form
    required_media_type = Mime[:url_encoded_form].to_s
    return if request.media_type == required_media_type

    render_oauth_error(error: :invalid_request, error_description: "Content-Type must be #{required_media_type}")
  end

  def validate_required_params
    missing_params = REQUIRED_PARAMS.reject { |required_param| params[required_param].present? }
    return if missing_params.empty?

    error_description = "Missing required #{"parameter".pluralize(missing_params.size)}: #{missing_params.join(', ')}"

    render_oauth_error(error: :invalid_request, error_description:)
  end

  def validate_grant_type
    return if params[:grant_type] == GRANT_TYPE
    render_oauth_error(error: :unsupported_grant_type, error_description: "This grant type is not supported")
  end

  def validate_subject_token_type
    return if params[:subject_token_type] == SUBJECT_TOKEN_TYPE
    render_oauth_error(error: :invalid_request, error_description: "This subject_token_type is invalid")
  end

  def verify_subject_token
    result = ExternalIdentities.domain.entra_subject_tokens.verify_subject_token(subject_token: params[:subject_token].to_s)

    if result.ok?
      @verified_subject_token = result.ok
      return
    end

    render_invalid_grant_from(result)
  end

  def ensure_business_in_feature_flag
    verified_business = business
    if verified_business.nil?
      return render_oauth_error(error: :invalid_grant, error_description: "subject_token tenant is not recognized")
    end

    return if FeatureFlag.vexi.enabled?(:entra_token_exchange, verified_business, default: false)
    render_oauth_error(error: :unauthorized_client, error_description: "grant type not permitted")
  end

  def set_current_tenant
    return unless GitHub.multi_tenant_enterprise?
    GitHub::CurrentTenant.set(resource_for_conditional_access)
  end

  def resolve_emu_user
    result = ExternalIdentities.domain.emu_users.by_business_and_oid(
      business: T.must_because(business) { "ensure_business_in_feature_flag halts the request when business is nil" },
      oid: verified_subject_token.claims["oid"].to_s
    )

    if result.ok?
      @resolved_emu_user = result.ok
      return
    end

    render_invalid_grant_from(result)
  end

  def validate_subject_token_authorized_party
    claims = verified_subject_token.claims
    authorized_party = claims["azp"] || claims["appid"]

    return if authorized_party == ENTRA_APPLICATION_ID

    render_oauth_error(error: :invalid_grant, error_description: "subject_token authorized party is not supported")
  end

  def resolve_application
    client_id = params[:client_id].to_s

    application = find_application(client_id)

    if application.nil?
      return render_oauth_error(error: :invalid_client, error_description: "Unknown client")
    end

    @resolved_application = application
  end

  def validate_client_authentication
    client_secret = params[:client_secret].to_s

    return if resolved_application.validate_client_secret(client_secret)

    render_oauth_error(error: :invalid_client, error_description: "client authentication failed")
  end

  def authorize_client_for_grant_type
    return if Apps::Privileged.capable?(:oauth_token_via_entra_exchange, app: resolved_application)

    # Temporary gate to allow us to test non production apps
    return if FeatureFlag.vexi.enabled?(:entra_token_exchange, resolved_application, default: false)

    render_oauth_error(error: :unauthorized_client, error_description: "client is not authorized to use the token exchange grant type")
  end

  sig { returns(ExternalIdentities::Domain::EntraSubjectTokens::VerifiedSubjectToken) }
  def verified_subject_token
    T.must_because(@verified_subject_token) { "verify_subject_token before_action populates this or halts the request" }
  end

  sig { returns(User) }
  def resolved_emu_user
    T.must_because(@resolved_emu_user) { "resolve_emu_user before_action populates this or halts the request" }
  end

  sig { returns(OauthApplication) }
  def resolved_application
    T.must_because(@resolved_application) { "resolve_application before_action populates this or halts the request" }
  end

  sig { returns(T.nilable(Business)) }
  memoize def business
    ActiveRecord::Base.connected_to(role: :reading) do
      Business.find_by(id: verified_subject_token.business_id)
    end
  end

  sig { params(client_id: String).returns(T.nilable(OauthApplication)) }
  def find_application(client_id)
    return nil if client_id.blank?

    ActiveRecord::Base.connected_to(role: :reading) do
      OauthApplication.find_by_key(client_id)
    end
  end

  sig { params(credential: OauthAccess, actor: User).void }
  def grant_authorized_org_credential_authorizations(credential:, actor:)
    authorized_organizations =
      ActiveRecord::Base.connected_to(role: :reading) do
        actor.organizations.to_a
      end

    cap_filter.authorized_resources(authorized_organizations).in_groups_of(100, false) do |organizations|
      Organization::CredentialAuthorization.grant_in_bulk(
        organizations: organizations, credential: credential, actor: actor
      )
    end
  end

  def resource_for_conditional_access
    T.must_because(business) { "ensure_business_in_feature_flag halts the request when business is nil" }
  end

  def enterprise_access_verification_enforceable
    :no
  end

  def tenant_verification_enforceable
    :no
  end

  def emu_visibility_enforceable
    :no
  end

  def emu_ownership_enforceable
    :no
  end

  def two_factor_enforceable
    :no
  end

  def external_conditional_access_policy_enforceable
    :no
  end

  def legacy_personal_access_tokens_enforceable
    :no
  end

  def personal_access_tokens_expiration_limit_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def stateless_request?
    true
  end

  def render_invalid_grant_from(result)
    render_oauth_error(error: :invalid_grant, error_description: T.must(T.must(result.error).message))
  end

  # Private: Render an OAuth HTTP error based on
  # https://www.rfc-editor.org/info/rfc6749/#section-5.2.
  #
  # error             - The Symbol representing error code.
  # error_description - The String text providing additional information, used
  #                     to assist the client developer in understanding the
  #                     error that occurred.
  # error_uri:        - The String identifying a human-readable web page with
  #                     information about the error, used to provide the client
  #                     developer with additional information about the error.
  #
  # Returns nothing.
  sig do
    params(
      error: Symbol,
      error_description: String,
      error_uri: T.nilable(String)
    ).void
  end
  def render_oauth_error(error:, error_description:, error_uri: nil)
    body = { error:, error_description: }
    body[:error_uri] = error_uri unless error_uri.nil?

    render json: body, status: 400
  end
end
