# typed: true
# frozen_string_literal: true

SecureHeaders::Configuration.default do |config|
  config.cookies = {
    httponly: { except: %w(_octo flash-notice flash-error flash-message flash-warn flash-success logout-was-successful color_mode preferred_coding_tools) },
    secure: GitHub.ssl? || SecureHeaders::OPT_OUT,
    samesite: {
      lax: { except: %w(oidc_csrf_token oidc_csrf_token_legacy saml_csrf_token saml_return_to saml_csrf_token_legacy saml_return_to_legacy social_csrf_token) },
      none: { only: %w(oidc_csrf_token saml_csrf_token saml_return_to social_csrf_token) }
    }
  }

  # Attempts to tell abobe products to ignore any crossdomain.xml files.
  # https://www.adobe.com/devnet-docs/acrobatetk/tools/AppSec/xdomain.html
  # Previously unapplied, we can enable later
  config.x_permitted_cross_domain_policies = SecureHeaders::OPT_OUT

  # Prevent file downloads from opening
  # http://msdn.microsoft.com/en-us/library/ie/jj542450(v=vs.85).aspx
  # Previously unapplied, we can enable later
  config.x_download_options = SecureHeaders::OPT_OUT

  # Sets the x-xss-protection header to enable client-side XSS protection.
  # The default is also "0", but we'll set it explicitly to be clear.
  config.x_xss_protection = "0"

  # Sets the x-content-type-options header to prevent content sniffing.
  # X-Content-Type-Options: nosniff
  config.x_content_type_options = SecureHeaders::XContentTypeOptions::DEFAULT_VALUE

  # Sets the strict transport security header to force use of SSL for all
  # connections.
  max_age = Rails.env.development? ? 1.minute : 365.days
  hsts_config = "max-age=#{max_age}; includeSubdomains".dup
  # The 'preload' value requests that the domain be added to Chrome's header
  # file of preloaded HSTS sites. This could be unexpected or unwanted on
  # Enterprise installs.
  hsts_config << "; preload" unless GitHub.enterprise?
  config.hsts = hsts_config.freeze

  # Sets the x-frames-options header to prevent clickjacking.
  config.x_frame_options = SecureHeaders::XFrameOptions::DENY

  # Sets the Content-Security-Policy header. Determines what a browser is
  # allowed to do.
  config.csp = {
    # Because safari doesn't follow the spec WRT schemeless sources,
    # we can't strip the schemes for non-SSL instances.
    preserve_schemes: !GitHub.ssl?,

    default_src: GitHub::CSP::Policy::DEFAULT_SOURCES,
    script_src: GitHub::CSP::Policy::SCRIPT_SOURCES,
    object_src: GitHub::CSP::Policy::OBJECT_SOURCES,
    style_src: GitHub::CSP::Policy::STYLE_SOURCES,
    img_src: GitHub::CSP::Policy::IMG_SOURCES,
    media_src: GitHub::CSP::Policy::MEDIA_SOURCES,
    frame_src: GitHub::CSP::Policy::FRAME_SOURCES,
    # Should enforce the same policy as `X-FRAME-OPTIONS`
    frame_ancestors: GitHub::CSP::Policy::FRAME_ANCESTORS,
    font_src: GitHub::CSP::Policy::FONT_SOURCES,
    connect_src: GitHub::CSP::Policy::CONNECT_SOURCES,
    base_uri: GitHub::CSP::Policy::BASE_URI_SOURCES,
    form_action: GitHub::CSP::Policy::FORM_ACTIONS,
    plugin_types: GitHub::CSP::Policy::PLUGIN_TYPES,
    manifest_src: GitHub::CSP::Policy::MANIFEST_SOURCES,
    worker_src: GitHub::CSP::Policy::WORKER_SOURCES,
    child_src: GitHub::CSP::Policy::CHILD_SOURCES,
    upgrade_insecure_requests: GitHub.ssl?,
  }.freeze

  config.referrer_policy = %w(
    origin-when-cross-origin
    strict-origin-when-cross-origin
  ).freeze
end

# Static file policy for static error pages
#
# This policy is used in conjuction with policies defined in `meta` tags
# within individual static files. These files could be served either with or
# without the CSP header added here via the Rails stack.
#
# A policy set in the CSP header can only be identical or restricted further
# in `meta` tags. Changes to this policy may also need to be reflected in the
# individual static files. Static files can be automatically updated by running
# the `script/update_static_csp` script.
#
# For now, per the discussion in https://github.com/github/github/pull/37758,
# a connect-src of `none` cannot be used because it will break safe browsing in
# Chrome on iOS. This should be restricted further in the meta tags for pages
# not requiring a connect-src once this bug is resolved.
#
SecureHeaders::Configuration.override(:static_file_policy) do |config|
  config.csp = {
    default_src: [SecureHeaders::PolicyManagement::NONE],
    script_src: [SecureHeaders::PolicyManagement::SELF],
    style_src: [SecureHeaders::PolicyManagement::UNSAFE_INLINE],
    img_src: [SecureHeaders::PolicyManagement::SELF, SecureHeaders::PolicyManagement::DATA_PROTOCOL],
    connect_src: [SecureHeaders::PolicyManagement::SELF],
    form_action: [SecureHeaders::PolicyManagement::SELF],
    base_uri: [SecureHeaders::PolicyManagement::SELF],
  }
end

# Report CSP violations for alternative policy configuration
SecureHeaders::Configuration.override(:multi_tenant_report_only) do |config|
  config.csp_report_only = config.csp
  config.csp_report_only[:img_src] = GitHub::CSP::Policy::IMG_SOURCES_MULTI_TENANT
  config.csp_report_only[:report_uri] = [GitHub.browser_errors_url + "?csp_enforcement=report-only"]
end

# Trusted Types report-only monitoring policy.
# Sends Content-Security-Policy-Report-Only with require-trusted-types-for so
# browsers report sink violations without blocking anything. Gated behind the
# trusted_types Vexi feature flag.
#
# The report-only policy intentionally does NOT mirror the enforced CSP — only
# Trusted Types directives (plus a permissive default-src to avoid fetch-noise
# reports) are sent. This avoids duplicating enforced CSP directives in the
# report-only header. See https://github.com/github/react-platform/issues/1849.
#
# Notes on the minimum shape required by the secure_headers gem:
#   - `default_src` is required by `validate_config!`; `*` is permissive so the
#     browser does not emit reports for ordinary fetches.
#   - `script_src` must also be present to satisfy validation. We use `%w(*)`
#     rather than `OPT_OUT` because `OPT_OUT` is a `NoOpHeaderConfig` instance
#     that cannot be merged by `append_content_security_policy_directives` (view-
#     level appenders call that method without an explicit target, causing the gem
#     to call `.to_a` on the existing value, which raises `NoMethodError`).
#     Using `*` is equivalent — it suppresses script-source violation reports
#     and is safely combineable with any appended values.
SecureHeaders::Configuration.override(:trusted_types_report_only) do |config|
  config.csp_report_only = {
    default_src: %w(*),
    script_src: %w(*),
    require_trusted_types_for: ["'script'"],
    trusted_types: [
      # For HTML strings sanitized on the client via @github-ui/sanitize before being passed to a sink.
      # Should not be used without a sanitization step.
      "github-sanitize",
      # For HTML strings that originated from the server and are treated as trusted.
      "github-server-html",
      # For static, hardcoded HTML string literals authored in client source code.
      # Should never be used with dynamic or user-controlled content.
      "github-unsafe-static",
      # Suppress reports for duplicate policy creation (e.g. from Turbo navigations).
      "'allow-duplicates'",
    ],
    report_uri: [GitHub.browser_errors_url],
  }
end

# Save some bytes and send a very terse and effective policy.
SecureHeaders::Configuration.override(:api) do |config|
  config.csp = {
    default_src: [SecureHeaders::PolicyManagement::NONE],
    script_src: SecureHeaders::OPT_OUT,
  }
end

# Package registry policy for package indices and access endpoints
#
# This policy is used by endpoints of the package registry. They are only
# accessed via CLI tooling so they do not need to be as permissive.
# Additionally, some package managers (looking at you apt) have hard limits
# on the header value length.
SecureHeaders::Configuration.override(:package_registry_policy) do |config|
  config.csp = {
    default_src: [SecureHeaders::PolicyManagement::NONE],
    script_src: [SecureHeaders::PolicyManagement::NONE],
    base_uri: [SecureHeaders::PolicyManagement::SELF],
    form_action: [SecureHeaders::PolicyManagement::NONE],
    frame_ancestors: [SecureHeaders::PolicyManagement::NONE],
    sandbox: true,
    upgrade_insecure_requests: GitHub.ssl?,
  }
end

# OctoCaptcha policy for displaying FunCaptcha as an iframe on dotcom
#
SecureHeaders::Configuration.override(:octocaptcha_policy) do |config|
  script_src = ["https://api.funcaptcha.com", "https://api.arkoselabs.com", "https://cdn.arkoselabs.com", "https://github-api.arkoselabs.com", SecureHeaders::PolicyManagement::UNSAFE_EVAL]
  script_src += GitHub::CSP::Policy::SCRIPT_SOURCES
  if Rails.env.development? || Rails.env.test?
    script_src += ["http://github.localhost", "http://octocaptcha.localhost"]
  end

  frame_ancestors = [GitHub.host_name, "*.#{GitHub.host_name}", "*.githubapp.com", "www-staging.npm.red", "www-sandbox.npm.red", "www.npmjs.com", "www-production.npmjs.com", "githubuniverse.com"]
  frame_ancestors = ["*"] if Rails.env.development?

  connect_src = ["https://api.funcaptcha.com", "https://api.arkoselabs.com", "https://github-api.arkoselabs.com"]
  connect_src += GitHub::CSP::Policy::CONNECT_SOURCES if Rails.env.development?
  connect_src += ["ws://octocaptcha.localhost"] if Rails.env.development?

  config.csp = {
    # Preserve https:// schemes so scripts from arkoselabs can load
    # when the page is served over http:// in development
    preserve_schemes: Rails.env.development?,
    frame_src: ["https://api.funcaptcha.com", "https://api.arkoselabs.com", "https://github-api.arkoselabs.com"],
    default_src: [SecureHeaders::PolicyManagement::NONE],
    connect_src: connect_src,
    style_src: GitHub::CSP::Policy::STYLE_SOURCES,
    script_src: script_src,
    base_uri: [SecureHeaders::PolicyManagement::SELF],
    form_action: [SecureHeaders::PolicyManagement::NONE],
    frame_ancestors: frame_ancestors,
    plugin_types: [],
    upgrade_insecure_requests: GitHub.ssl?,
  }

  config.x_frame_options = SecureHeaders::XFrameOptions::ALLOW_ALL
end

# Configuration override to send the Clear-Site-Data header.
SecureHeaders::Configuration.override(:clear_browser_cache) do |config|
  config.clear_site_data = [
    SecureHeaders::ClearSiteData::CACHE,
  ]
end

# Configuration override to opt-out of setting Referrer-Policy header
SecureHeaders::Configuration.override(:disable_referrer_policy) do |config|
  config.referrer_policy = "no-referrer-when-downgrade"
end

# Configuration override to set same-origin Referrer-Policy header
SecureHeaders::Configuration.override(:same_origin_referrer_policy) do |config|
  config.referrer_policy = %w(same-origin).freeze
end

if Rails.env.development?
  ActionDispatch::DebugExceptions.register_interceptor do |request, _exception|
    SecureHeaders.append_content_security_policy_directives(request, {
      script_src: %w('unsafe-inline')
    })
  end

  ActiveSupport.on_load(:action_controller) do
    Rails::InfoController.before_action do
      T.bind(self, Rails::InfoController)
      SecureHeaders.append_content_security_policy_directives(request, { script_src: %w('unsafe-inline') })
    end

    Rails::MailersController.before_action do
      T.bind(self, Rails::MailersController)
      SecureHeaders.append_content_security_policy_directives(request, {
        frame_src: [SecureHeaders::PolicyManagement::SELF],
        frame_ancestors: [SecureHeaders::PolicyManagement::SELF],
      })
    end
  end
end
