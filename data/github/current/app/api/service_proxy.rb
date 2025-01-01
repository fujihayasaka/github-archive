# typed: true
# frozen_string_literal: true

# A reverse proxy to Information Retrieval (IR) backends that support REST APIs with open api schemas. Handles
# authentication, feature flags, and rate limiting.
#
# Currently used for code search (blackbird), semantic search (cardinal), and embeddings/chunks (aip).
#
# TODO: We could have a base proxy app and then subclass that for each backend. This might make rate limiting
# configuration a bit nicer...
class Api::ServiceProxy < Api::App
  # Rate limits are dynamic based on the route. These are overall backstop rate limits. The individual services
  # themselves have cost-based rate limiting quotas.
  #
  # TODO: This needs to be more dynamic (or maybe related to the backend?), not great to re-match the route path...
  def rate_limit_configuration
    family = case request.path_info
    when %r(^/chunks),
         %r(^/code),
         %r{^/symbols}
      # Higher limits for code search, and general analysis
      Api::RateLimitConfiguration::BLACKBIRD_TIER2_FAMILY
    else
      # Embeddings are expensive to generate, so we have a lower rate limit.
      # Default to the lower (tier1) limit for everything else.
      Api::RateLimitConfiguration::BLACKBIRD_TIER1_FAMILY
    end
    Api::RateLimitConfiguration.for(family, self)
  end

  before do
    deliver_error! 404 if GitHub.enterprise?
    deliver_error! 404 unless logged_in?
    deliver_error! 404 unless current_user.feature_enabled?(:blackbird_api_preview)
  end

  # Cardinal embeddings search.
  get "/embeddings*", operation_id: :ignored do
    @route_owner = "@github/blackbird"
    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Check for a valid copilot license
    authorizer = Copilot::User.new(current_user).copilot_authorizer_object_no_snippy
    deliver_error! 404 unless authorizer.access_allowed?

    proxy_req!(:cardinal_query)
  end

  # Cardinal generates embeddings and chunks
  post %r{/(chunks|embeddings)}, operation_id: :ignored do
    # NB: POST requests connect to the primary db by default, we don't want that
    ActiveRecord::Base.connected_to(role: :reading) do
      @route_owner = "@github/blackbird"
      control_access :authenticated_user,
        resource: current_user,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      # Check for a valid copilot license
      authorizer = Copilot::User.new(current_user).copilot_authorizer_object_no_snippy
      deliver_error! 404 unless authorizer.access_allowed?

      proxy_req!(:blackbird_analysis)
    end
  end

  # Blackbird code search
  get "/code*", operation_id: :ignored do
    @route_owner = "@github/blackbird"
    control_access :authenticated_user,
      resource: current_user,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    proxy_req!(:blackbird_query)
  end

  # Blackbird analysis parses code to produce symbol data.
  post "/symbols*", operation_id: :ignored do
    # NB: POST requests connect to the primary db by default, we don't want that
    ActiveRecord::Base.connected_to(role: :reading) do
      @route_owner = "@github/blackbird"
      control_access :authenticated_user,
        resource: current_user,
        allow_integrations: true,
        allow_user_via_granular_actor: true

      proxy_req!(:blackbird_analysis, include_actor: false)
    end
  end

  private

  BACKENDS = {
    blackbird_query: {
      url: GitHub.blackbird_mw_query_url.sub("twirp", "api"),
      hmac_key: GitHub.blackbird_mw_query_hmac_key,
    },
    blackbird_analysis: {
      url: GitHub.blackbird_mw_analysis_url.sub("twirp", "api"),
      hmac_key: GitHub.blackbird_mw_analysis_hmac_key,
    },
    cardinal_query: {
      url: GitHub.cardinal_mw_query_url.sub("twirp", "api"),
      hmac_key: GitHub.cardinal_mw_query_hmac_key,
    },
    cardinal_analysis: {
      url: GitHub.cardinal_mw_analysis_url.sub("twirp", "api"),
      hmac_key: GitHub.cardinal_mw_analysis_hmac_key,
    }
  }

  # Basic idea from: https://github.com/lonre/rack-forward with modifications.
  def proxy_req!(backend, include_actor: true)
    deliver_error! 404 unless backend = BACKENDS[backend]

    req = Rack::Request.new(env)
    method = req.request_method
    uri = URI.parse("#{backend[:url]}#{req.path}?#{req.query_string}")
    r = Net::HTTP.const_get(method.capitalize).new("#{uri.path}#{"?" if uri.query}#{uri.query}")

    if r.request_body_permitted? && req.body
      r.body_stream = req.body
      r.content_length = req.content_length
      r.content_type = req.content_type
    end

    r["Accept-Encoding"] = req.accept_encoding
    r["Accept"] = req.env["HTTP_ACCEPT"]
    r["Authorization"] = req.env["HTTP_AUTHORIZATION"]
    r["Referer"] = req.referer
    r["Request-HMAC"] = hmac_token(backend[:hmac_key]) unless backend[:hmac_key].blank?
    r["X-Forwarded-For"] = (req.env["X-Forwarded-For"].to_s.split(/, */) + [req.env["REMOTE_ADDR"]]).join(", ")
    r["X-GitHub-Api-Version"] = req.env["HTTP_X_GITHUB_API_VERSION"]
    r["X-GitHub-Base-Url"] = req.base_url
    r["X-GitHub-Request-Id"] = req.env["HTTP_X_GITHUB_REQUEST_ID"]
    r["X-GLB-Via"] = "hostname=#{GitHub.local_host_name} t=#{Time.now.to_f}"

    if include_actor
      r["X-GitHub-Actor-Id"] = current_user.id
      r["X-GitHub-Actor-Access-Token"] = api_auth.token
      r["X-GitHub-Actor-Request-Ip"] = remote_ip
      r["X-GitHub-Actor-Session-Id"] = AuthenticationToken.hash_token(api_auth.token)
    end

    GitHub.logger.info("ServiceProxy sending request to backend",
      "code.namespace": self.class.name,
      "gh.user.id": current_user.id,
      "gh.request_id": req.env["HTTP_X_GITHUB_REQUEST_ID"],
      "serviceproxy.backend.url": backend[:url],
      "serviceproxy.backend.path": req.path,
      "serviceproxy.backend.method": method
    )

    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      http.request(r)
    end

    headers = {}
    resp.each_header do |k, v|
      headers[k] = v unless k.to_s =~ /cookie|content-length|transfer-encoding/i
    end

    [resp.code.to_i, headers, [resp.read_body]]
  end

  # NB: Identical to lib/github/faraday_middleware/hmac_auth.rb
  def hmac_token(hmac_key)
    return "" if hmac_key.blank?
    timestamp = Time.now.to_i.to_s
    digest = OpenSSL::Digest::SHA256.new
    hmac = OpenSSL::HMAC.new(hmac_key, digest)
    hmac << timestamp
    "#{timestamp}.#{hmac}"
  end
end
