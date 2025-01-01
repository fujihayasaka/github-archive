# typed: true
# frozen_string_literal: true

module ApplicationController::CookiesDependency
  # Cookies that may be set on any user visiting the site.
  ANONYMOUS_COOKIES = Set.new([
    # This cookie is used for temporary application and framework state between
    # pages like what step the user is on in a multiple step form.
    #
    # Blocking this cookie will break core functionality of the site.
    :_gh_sess,

    # This cookie is used by Google Analytics.
    #
    # Blocking this cookie will not break any functionality.
    :_ga,

    # This cookie is used by Octolytics to distinguish unique users and clients
    #
    # Blocking this cookie will break login device tracking
    :_octo,

    # Used to track devices used to sign in across users, but only
    # on dotcom/gist
    :_device_id,

    # This cookie tracks the referring source for signup analytics.
    #
    # TODO: Consider a more clear name. Could maybe be moved into session.
    #
    # Blocking this cookie will not break signup functionality.
    :tracker,

    # This cookie used a hint that the user is already logged in.
    #
    # Blocking this cookie may break automatic log on into gist.github.com
    #
    # TODO: We should only need to set this on logged in users
    :logged_in,

    # This cookie is set by client-side javascript to the browsers configured
    # timezone. The server reads the value to automatically adjust displayed
    # date and times to users timezone. It is also used to create git commits
    # with the proper timezone.
    #
    # Blocking this cookie may degrade some functionality. The timezone is
    # assumed to be UTC if unset.
    :tz,

    # This cookie is set by SAML auth path method. The application sets the
    # cookie to associate the CSRF token with the client, the CSRF token is
    # also recorded in GitHub::KV and associated with a SAML AuthN request id. This
    # prevents a login attack if an attacker has access to an authenticated
    # response
    :saml_csrf_token,
    :saml_csrf_token_legacy,

    # This cookie is set by OIDC auth path method. The application sets the
    # cookie to associate the CSRF token with the client, the CSRF token is
    # also recorded in GitHub::KV and associated with a OIDC AuthN request id. This
    # prevents a login attack if an attacker has access to an authenticated
    # response
    :oidc_csrf_token,
    :oidc_csrf_token_legacy,

    # This cookie is set by the SAML auth path method. The application sets
    # this cookie to maintain state during the SAML authentication loop.
    :saml_return_to,
    :saml_return_to_legacy,

    # This cookie is set by Gist during the start of the oauth flow
    # It is used to ensure the user that started the oauth flow is the
    # same user that completes it, protecting against login CSRFs
    :gist_oauth_csrf,

    # This cookie is used during organization transforms to give a hint
    # on the login page.
    :org_transform_notice,

    # These cookies are used to set flash messages for logged out (cached) views.
    :"flash-notice",
    :"flash-error",
    :"flash-message",
    :"flash-warn",

    # Used to indicate to JS that a logout occurred and some cleanup actions should be taken
    :"logout-was-successful",

    # This cookie is used during the App Manifest flow to maintain state during
    # the redirect to fetch a user session.
    :app_manifest_token,

    # This cookie is used to disable the global site banners
    # It can contain multiple comma separated values, each representing the UID of a banner
    :disabled_global_site_banners
  ])
  if Rails.env.development?
    # This cookie is used to set Proxima tenant in development mode
    ANONYMOUS_COOKIES << :gh_tenant
  end
  ANONYMOUS_COOKIES.freeze

  # Cookies that may be set while a user is logged in.
  AUTHENTICATED_COOKIES = Set.new([
    # This cookie is used to log you in.
    #
    # Blocking this cookie will prevent the user from staying logged in.
    :user_session,

    # This cookie is set to ensure that browsers that support SameSite cookies
    # have a cookie to check to ensure a request originates from GitHub to
    # help prevent CSRF.
    ApplicationController::UserSessionDependency::USER_SESSION_COOKIE_SAME_SITE,

    # This cookie is used by Gist when running on a separate host.
    #
    # Blocking this cookie will prevent the user from staying logged in to Gist.
    :gist_user_session,

    # This cookie is set to ensure that browsers that support SameSite cookies
    # have a cookie to check to ensure a request originates from GitHub to
    # help prevent CSRF.
    ApplicationController::UserSessionDependency::GIST_USER_SESSION_COOKIE_SAME_SITE,

    # This cookie used a hint that the user is already logged in.
    #
    # Blocking this cookie may break automatic log on into gist.github.com
    #
    # TODO: This cookie should fully replace the :logged_in cookie.
    :dotcom_user,

    # When Enterprise is configured to run on multiple subdomains, this cookie
    # is used to authenticate requests to those subdomains via an nginx module.
    #
    # Blocking this cookie would prevent the user from accessing subdomains on
    # GitHub Enterprise.
    GitHub.allow_private_mode_user_session_cookie? ? :private_mode_user_session : nil,

    # This cookie is used to persist the `suggested_target_id` parameter through
    # the marketplace installation flow.
    :marketplace_suggested_target_id,

    # This cookie is used to persist the `repository_ids` parameter through
    # the marketplace installation flow.
    :marketplace_repository_ids,

    # Cookie to set color mode and theme for authenticated users
    :color_mode,

    # This cookie is used to track the preferred OS appearance for authenticated users
    :preferred_color_mode,

    # This cookie is used to make it possible for users coming from the
    # enterprise trial signup flow to be redirected back to the organization page.
    #
    # This is useful when the signup flow is handled by an external site. For example, resources.github.com.
    :enterprise_trial_redirect_to,

    # This cookie is used to store user sessions for accounts that the user has "added"
    # on the current device. This is used for the "AccountSwitcher" feature.
    #
    # Session keys are encoded along with the associated user ID. This cookie may contain
    # entries for both valid and invalid session.
    :saved_user_sessions
  ].compact).freeze

  # Cookies that are only set for staff users.
  STAFF_COOKIES = Set.new([
    # Used to allow access to staff environments
    GitHub::StaffOnlyCookie::NAME,
    :site,

    # Used to route traffic to a specific haproxy backend
    :haproxy_backend,

    # Used to opt out of using canary unicorns
    :staff_canary_opt_out,

    # Used in combination with a staff cookie to skip spam checks on signup
    :skip_signup_spam_checks,
  ]).freeze

  # Set of all whitelisted cookies
  COOKIES = (
    ANONYMOUS_COOKIES +
    AUTHENTICATED_COOKIES +
    STAFF_COOKIES
  ).freeze

  private

  def cookies
    @_allowlisted_cookie_jar ||= GitHub::AllowlistedCookieJar.new(super, COOKIES)
  end
end
