# typed: false
# frozen_string_literal: true

class Api::Internal::Pages < Api::Internal
  # Internal: Given a page id and a signed user session token, this endpoint
  # checks if the token is valid and returns a status :ok
  post "/internal/pages/auth", operation_id: :internal do
    @route_owner = "@github/pe-issues-projects"

    log_data.update({
      "gh.page.subdomain" => page_subdomain,
      "gh.page.id" => data["page_id"]&.to_i,
      "gh.repo.id" => page&.repository&.id,
      "gh.catalog_service" => "github/pages",
      "gh.user.id" => user&.id,
    })

    if token.blank?
      deliver_error! 400, message: "property 'token' is required in request body"
    end

    unless page
      deliver_error! 404, message: "page does not exist"
    end

    if integration_token
      ensure_app_token_is_valid!(integration_token)
    else
      ensure_session_is_valid!(auth_token)
    end

    unless page.repository.pullable_by?(user)
      deliver_error! 403, message: differentiate_403s? ? :access_forbidden : "user does not have read access to the repository"
    end

    if user&.is_enterprise_managed? && user.enterprise_managed_business&.idp_cap_for_web_enabled?
      if enforce_conditional_access_policies(page, policies: [:ip_allowlist, :external_conditional_access_policy]) != :ok
        deliver_error! 403, message: differentiate_403s? ? :ip_forbidden : forbidden_message
      end
    else
      if enforce_conditional_access_policies(page, policies: [:ip_allowlist]) != :ok
        deliver_error! 403, message: differentiate_403s? ? :ip_forbidden : forbidden_message
      end
    end

    if auth_token && saml_enforcement_policy_for(page.repository.owner, auth_token.user).try(:enforced?)
      repository = page.repository

      deliver_error!(403, message: differentiate_403s? ? :saml_session_not_found : "no active saml sessions found.") unless
        user_saml_authorized?(auth_token, repository, remote_ip)
    end

    # `true` is for validity, which we already checked in `ensure_session_is_valid!`
    # and `ensure_app_token_is_valid!`
    deliver :internal_token_validation_output, true, repo: page.repository, status: 200
  end

  post "/internal/pages/build", operation_id: :internal do
    @route_owner = "@github/pages-reviewers"

    _ = receive_with_schema("internal_page", "build-page", skip_validation: true)
    GitHub.logger.info(
                "gh.pages.token" => token,
                "gh.pages.id" => page_id,
                "gh.pages.ip.address" => ip_for_allowed_check,
                "code.function" => "post-internal-pages-build",
                "gh.catalog_service" => "github/pages"
              )

    deliver_error!(404, message: "Page was not found.") if page.nil?

    PageLazyBuildJob.set(queue: page.page_queue).perform_later(page_id)

    deliver_raw({ status: "ok" }, status: 202)
  end if GitHub.pages_lazy_builds_enabled?

  def deliver_error!(status, options = {})
    GitHub.logger.info(
      "Internal Pages API request error: #{options[:message]}",
      "http.status_code" => status
    )
    super(status, options)
  end

  def authenticated_for_private_mode?
    return true if request.path_info == "/internal/pages/build"

    super
  end

  private

  def data
    return @data if defined? @data
    @data = receive_with_schema("internal_page", "validate-pages-token", skip_validation: true)
  end

  def ip_for_allowed_check
    data["ip_address"].to_s
  end

  def token
    data["token"].to_s
  end

  def page_id
    data["page_id"].to_i
  end

  def page_subdomain
    if GitHub.multi_tenant_enterprise?
      "#{data["page_subdomain"]}_#{GitHub::CurrentTenant.get.shortcode}"
    else
      data["page_subdomain"].presence
    end
  end

  def page
    return @page if defined? @page
    @page = if data.key?("page_id")
      Page.find_by_id(page_id)
    # don't just check if key is present, check that value is truthy
    elsif data["page_subdomain"] && GitHub.flipper[:pages_auth_controller_accepts_subdomain].enabled?
      Page.where(subdomain: page_subdomain).or(Page.where(custom_subdomain: page_subdomain)).first
    end
  end

  def user
    if allow_integration_tokens? && integration_token
      integration_token.user
    elsif auth_token
      auth_token.user
    end
  end

  def auth_token
    return @auth_token if defined? @auth_token
    return @auth_token = nil unless page.present?
    return @auth_token = nil if token.start_with?(AuthenticationToken.access_token_prefix)
    @auth_token = GitHub::Authentication::SignedAuthToken::Session.verify(
      token: token,
      scope: page.auth_token_scope,
    )
  end

  def integration_token
    return @integration_token if defined? @integration_token
    return @integration_token = nil unless allow_integration_tokens?
    return @integration_token = nil unless token.start_with?(AuthenticationToken.access_token_prefix)
    attempt = GitHub::Authentication::Attempt.new(
      token: token,
      allow_integrations: true,
      from: :pages_internal_auth_api,
      ip: remote_ip,
      user_agent: user_agent,
      url: Rack::RequestLogger.url_for_logging(request.url),
      request_id: request.env["HTTP_X_GITHUB_REQUEST_ID"],
    )
    @integration_token = attempt.result
  end

  def actor_for_conditional_access
    user
  end

  def account_switcher_enabled?
    return false unless auth_token && auth_token.valid? && auth_token.user

    !GitHub.enterprise?
  end

  def externally_accessible?
    false
  end

  def require_request_hmac?
    true
  end

  def saml_enforcement_policy_for(owner, current_user)
    return unless owner&.respond_to?(:external_identity_session_owner)

    provider_owner = owner.external_identity_session_owner
    case provider_owner
    when ::Organization
      Organization::SamlEnforcementPolicy.new(organization: provider_owner, user: current_user)
    when ::Business
      organization = owner.is_a?(::Organization) ? owner : nil
      Business::SamlEnforcementPolicy.new(business: provider_owner, organization: organization, user: current_user)
    end
  end

  def user_saml_authorized?(auth_token, repository, remote_ip)
    filter = ConditionalAccess::Model::Filter.new(self,
      actor: auth_token.user,
      web_session: auth_token.session,
      remote_ip: remote_ip,
      location: :api)
    user_can_access_repository?(repository, filter)
  end

  def user_can_access_repository?(repository, filter)
    repo_ids = filter.authorized_resource_ids([repository], exclude: [:ip_allowlist, :external_conditional_access_policy])

    repo_ids.include?(repository.id).tap do |result|
      GitHub.logger.info("User is not authorized to access this repo according to CAP filter") unless
        result == true
    end
  end

  def differentiate_403s?
    page.repository.feature_enabled?(:pages_differentiate_403s) ||
      page.repository.owner.feature_enabled?(:pages_differentiate_403s)
  end

  def allow_integration_tokens?
    return false unless page
    page.repository.feature_enabled?(:pages_access_integration_token) ||
      page.repository.owner.feature_enabled?(:pages_access_integration_token)
  end

  def session_token_invalid_reason(token)
    unless token.valid?
      if token.bad_token?
        return "token format is invalid"
      elsif token.bad_scope?
        return "token is not valid within the scope of this page"
      elsif token.bad_login?
        return "token has an invalid user id"
      elsif token.expired?
        return "token has expired"
      elsif token.user_suspended?
        return "token is for a suspended user"
      elsif token.session_expired?
        return "token's session has expired"
      elsif token.session_revoked?
        return "token's session has been revoked"
      else
        return "token is malformed or has been tampered with"
      end
    end

    if account_switcher_enabled? && !token.session.in_use?
      "token's session is not in use"
    end
  end

  def ensure_session_is_valid!(token)
    reason = session_token_invalid_reason(token)
    if reason
      log_data.update(
        token_kind: "session",
        token_invalid_reason: reason
      )
      deliver_error! 401, message: reason
    end
  end

  def app_token_invalid_reason(token)
    unless token.success?
      if token.allow_user_via_granular_actor_failure?
        "GitHub App user access tokens are not allowed"
      elsif token.token_failure?
        "Token is invalid"
      elsif token.suspended_failure?
        "Invalid credentials"
      elsif (token.suspended_integration_failure? ||
        token.suspended_oauth_application_failure? ||
        token.application_owned_by_spammy_failure?)
        "Application is suspended"
      elsif token.suspended_installation_failure?
        "App installation is suspended"
      else
        "Token is invalid"
      end
    end
  end

  def ensure_app_token_is_valid!(token)
    return if token.nil?
    reason = app_token_invalid_reason(token)
    if reason
      log_data.update(
        token_kind: "app",
        token_invalid_reason: reason
      )
      deliver_error! 401, message: reason
    end
  end
end
