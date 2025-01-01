# typed: true
# frozen_string_literal: true

module ApplicationController::MultiTenantEnterpriseDependency
  extend T::Helpers
  requires_ancestor { ApplicationController }

  PRIVATE_MODE_IGNORE_PATHS = %r{\A(
    # Authentication
    /login(/.*)?|
    /logout|
    /switch_account|
    /sessions?(/.*)?|
    /auth/.*|
    /saml/.*|
    /oidc/.*|
    /auth/oidc/callback|
    /enterprises/.*/sso(.*)?|
    /enterprises/.*/saml/.*|
    /enterprises/.*/oidc/.*|
    /sso_login(/.*)?|
    /password_reset(/.*)?|
    /users/password|
    /u2f/trusted_facets|
    /u2f/login_fragment|

    # Dashboard
    # /dashboard|
    # /dashboard/logged_out|

    # Web app manifest file
    /manifest\.json|

    # Assets
    /assets-cdn/worker/.*|

    # Suspended users get sent here
    /suspended|

    # DashboardController ATOM/JSON feeds.
    /[a-z0-9][a-z0-9-]*\.private(\.actor)?\.(atom|json)|

    # Notifications endpoint for marking read email notifications as read.
    /notifications/beacon/.*\.gif|

    # GitHub for Windows uses this to determine whether a host is an
    # enterprise instance or not (separate sign in flow to support 2fa)
    # See https://github.com/github/Windows/issues/3431
    /site/sha|

    # Integration tests use this to get the API URL for the tenant
    /site/metadata|

    # For monitoring
    /status
  )\Z}x

  # Check to see if Private Mode is enabled. If enabled, send the user to the
  # login page unless it's the first run.
  def enforce_multi_tenant_private_mode
    return unless enforce_multi_tenant_private_mode?

    return_to = params[:return_to]
    return_to ||= request.url if request.url.chomp("/") != GitHub.url.chomp("/")
    redirect_to_login(return_to)
  end

  def enforce_multi_tenant_private_mode?
    return unless GitHub.multi_tenant_enterprise?
    GitHub.private_mode_enabled? &&
      GitHub.flipper[:enforce_mt_private_mode_for_web].enabled? &&
      !private_mode_authenticated? &&
      request.path_info !~ PRIVATE_MODE_IGNORE_PATHS
  end

  def private_mode_authenticated?
    logged_in? || GitHub::PrivateModeMiddleware.valid_private_mode_session?(cookies)
  end

  def multi_tenant_enterprise?
    GitHub.multi_tenant_enterprise?
  end

end
