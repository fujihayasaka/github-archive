# typed: true
# frozen_string_literal: true

# utility lib for random OAuth2 crap.
module OauthUtil
  extend self

  include Kernel

  # Hash of Symbol explanation identifiers and their corresponding String
  # textual descriptions. DO NOT modify existing key names in this Hash, as the
  # keys are used to lookup the textual descriptions in the audit log. If the
  # key names change, the audit log will be unable to lookup the associated
  # description for the event. However, feel free to update the textual
  # descriptions and add additional keys/values for new destroy explanations.
  VALID_DESTROY_EXPLANATIONS = {
    # Access/authorization was automatically deleted by
    # jobs/stale_oauth_tokens.rb because it had not been used in an extended
    # period.
    stale: "deleted automatically (not recently used)",

    # Access/authorization was automatically deleted because its
    # expiration date was reached.
    expired: "expired",

    # Access/authorization was destroyed by an OAuth application by using the
    # API or the Web UI
    oauth_application: "deleted by associated OAuth application",

    # Access/authorization was destroyed by an Integration by using the
    # API or the Web UI
    integration: "deleted by associated GitHub application",

    # Access/authorization was destroyed by a user using
    # https://developer.github.com/v3/oauth_authorizations/#delete-an-
    # authorization.
    api_user: "deleted using the GitHub Authorizations API",

    # Access/authorization was deleted by the user manually on github.com.
    web_user: "deleted on #{GitHub.host_name}",

    # Access/authorization was deleted by a site admin in stafftools on
    # github.com.
    site_admin: "deleted by #{GitHub.host_name} administrator",

    # Access/authorization was deleted as part of a mass revocation by an
    # organization administrator
    org_admin: "deleted by organization administrator",

    # Access/authorization was deleted as part of an automated token scan
    token_scan: "deleted automatically (found in a public repository)",

    # Access/authorization was deleted by a user explicitly if token is found in a private repository.
    token_scan_revoked_by_user_in_private_repo: "revoked by a user (token found in a private repository)",

    # Access was deleted because the maximum number of accesses for a given
    # (user, application, scope) was exceeded. The least recently used
    # access was destroyed.
    max_for_app: "deleted automatically (max accesses for application)",

    # Access/authorization was destroyed because the user changed their
    # password.
    password_changed: "deleted automatically (password changed)",

    # Access/authorization was destroyed because the user reset their
    # password.
    password_reset: "deleted automatically (password reset)",

    # Access/authorization was destroyed because the password was randomized.
    password_randomized: "deleted automatically (password randomized)",

    # Access/authorization was destroyed because the user logged out of DotCom
    # and this is an internal application associated GitHub
    logged_out: "deleted by associated GitHub OAuth application (user logged out)"
  }.freeze

  VALID_REVOKE_REASONS = {
    # Access was revoked because secret scanning detected the token
    secret_scanning: "revoked by GitHub secret scanning",

    # Access was revoked because it was anonymously submitted to the API revocation endpoint
    revocation_api: "revoked by the GitHub API token revocation endpoint",
  }.freeze

  def revoke_reason(reason)
    VALID_REVOKE_REASONS[reason]
  end

  def destroy_explanation(explanation)
    VALID_DESTROY_EXPLANATIONS[explanation]
  end

  RESERVED_REDIRECT_URI_QUERY_KEYS = %w(
    code
    state
    browser_session_id
  ).freeze

  VALID_LOCALHOSTS = %w(
    localhost
    127.0.0.1
  )

  def valid_redirect_uri?(app, url)
    return true if url.to_s == "https://github.com/login/oauth/success"

    if app.strict_callback_url_validation?
      app.application_callback_urls.any? do |registered_url|
        !bad_strict_redirect_uri?(registered_url.url, url)
      end
    else
      !bad_redirect_uri?(app, url)
    end
  end

  def bad_redirect_uri?(app, url)
    return false if url.to_s == "https://github.com/login/oauth/success"

    # Check for blank url
    if url.to_s.blank?
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:callback_url_blank"]
      return true
    end

    if app.callback_url_direct_match?(url.to_s)
      return false
    else
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:callback_url_bad_match"]
      GitHub.logger.info(
        "gh.oauth.method" => "bad_redirect_uri?",
        "gh.oauth.passed_callback" => url,
        "gh.oauth_application.id" => app.id)
    end

    configured = app.callback_uri

    unless configured
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:callback_uri_missing"]
      return true
    end

    attempted = case url
    when Addressable::URI
      url
    when String
      begin
        Addressable::URI.parse(url)
      rescue Addressable::URI::InvalidURIError
        return true
      end
    else
      raise ArgumentError
    end

    # Check for non-printable characters
    unless attempted.to_s =~ /\A[[:graph:]]*\z/
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_bytes"]
      return true
    end

    # Check that the schemes match
    unless configured.normalized_scheme == attempted.normalized_scheme
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_scheme"]
      return true
    end

    # Disallow a few sketchy schemes
    if IntegrationUrl::BLOCKED_SCHEMES.include? attempted.normalized_scheme
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_scheme"]
      return true
    end

    # Check that the username/password info matches
    unless configured.normalized_userinfo == attempted.normalized_userinfo
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_userinfo"]
      return true
    end

    # If someone tries to do any crafting with backslashes, reject it.
    # Also guard against missing or extra / between scheme and host. github/github#46694.
    unless UrlHelper.valid_host?(attempted.host)
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_hostname"]
      return true
    end

    # Check that the domains match or that the attempted domain is a subdomain
    # of the configured domain.
    unless configured.normalized_host == attempted.normalized_host
      if subdomain? configured.normalized_host, attempted.normalized_host
        GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:nonexplicit_subdomain_used"]
      else
        GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_hostname"]
        return true
      end
    end

    # Check that the (inferred) ports match
    unless configured.inferred_port == attempted.inferred_port
      unless localhost?(configured.normalized_host)
        GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_port"]
        return true
      end
    end

    # Check that the paths match, or that the attempted path is a subpath of
    # the configured path.
    configured_path = configured.normalized_path.chomp "/"

    # We need to percent unescape here and check again for backslashs and ..
    # This is because normalized_path doesn't work with unescaping properly and
    # browsers do honor this.
    attempted_path  = Addressable::URI.unescape(
      attempted.normalized_path.chomp("/")
    )

    if attempted_path.include?('\\') || attempted_path.include?("..") # rubocop:disable Style/StringLiterals
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_path"]
      return true
    end

    if attempted_path !~ /\A[[:graph:]]*\z/
      GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_path"]
      return true
    end

    unless configured_path == attempted_path
      if subpath?(configured_path, attempted_path)
        GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:nonexplicit_path_used"]
      else
        GitHub.dogstats.increment "auth.oauth", tags: ["action:bad_redirect_uri", "error:bad_path"]
        return true
      end
    end

    # All the checks passed
    false
  end

  def bad_strict_redirect_uri?(registered_url, url)
    return false if registered_url == url

    configured = Addressable::URI.parse(registered_url)
    attempted  = case url
    when Addressable::URI
      url
    when String
      begin
        Addressable::URI.parse(url)
      rescue Addressable::URI::InvalidURIError
        return true
      end
    else
      raise ArgumentError
    end

    return true unless localhost?(configured.normalized_host)

    # Nil out the port since we don't care about that for localhost traffic.
    #
    # Example:
    #   a = Addressable::URI.parse("https://foo:bar@localhost:1234/blah/yada?boo=blah")
    #
    #   a.to_s
    #   => "https://foo:bar@localhost:1234/blah/yada?boo=blah"
    #
    #   a.port = nil
    #   => nil
    #
    #   a.to_s
    #   => "https://foo:bar@localhost/blah/yada?boo=blah"
    configured.port = nil
    attempted.port  = nil

    configured.to_s != attempted.to_s
  end

  # Adds the params hash as GET params on the given base URI.  This builds
  # the OAuth2 redirection URL for web app clients.
  #
  # url    - String base URL for the client.
  # params - Hash of key/value pairs to be sent to the client.
  #
  # Returns a String URL.
  def redirect_url(url, params)
    base_url_and_query_string, fragment = url.to_s.split("#", 2)
    base_url, query_string = base_url_and_query_string.to_s.split("?", 2)
    separator = query_string.present? ? "&" : ""
    # Prefer removing `nil` values intead of sending an empty value in the
    # query string.
    params = params.delete_if { |_param, value| value.nil? }
    # Add tenant context for Proxima environments
    if GitHub.multi_tenant_enterprise?
      params[:github_host] = GitHub.host_name_with_tenant
    end

    query_string = [
      query_string.to_s,
      params.to_query,
    ].join(separator)

    url = base_url
    url << "?#{query_string}" if query_string.present?
    url << "##{fragment}" if fragment.present?

    url
  end

  # Check if a child domain is a subdomain of a parent domain.
  def subdomain?(parent, child)
    # Set the `limit` argument in `String#split` to -1 so that any trailing dots
    # are not lost when doing the subdomain check.
    parent = parent.split(".", -1).reverse
    child  = child.split(".", -1).reverse
    parent.zip(child).all? { |p, c| p == c }
  end

  # Check if the paths match exactly or if the child path is a subdirectory of
  # the parent path.
  def subpath?(parent, child)
    parent = parent.split "/"
    child  = child.split "/"
    parent.zip(child).all? { |p, c| p == c }
  end

  def localhost?(host)
    VALID_LOCALHOSTS.include?(host)
  end
end
