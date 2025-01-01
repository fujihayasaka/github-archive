# typed: true
# frozen_string_literal: true

# A reverse proxy that support REST APIs with OpenAPI schemas. Handles authentication, authorization, license checks,
# feature flags, and backstop rate limiting.
#
# Currently used for lexical code search, semantic search, and embeddings/chunks.
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
    when %r(\A/embeddings/code/search),
         %r(\A/code/search)
      # Lower (tier1) limit for: semantic search and lexical code search
      Api::RateLimitConfiguration::BLACKBIRD_TIER1_FAMILY
    else
      if current_user&.feature_flag_enabled?(:blackbird_clientside_indexing, default: false)
        # Highest (tier3) limit for chunking and embedding. Intended for testing local indexing.
        Api::RateLimitConfiguration::BLACKBIRD_TIER3_FAMILY
      else
        # Higher (tier2) limit for chunking and embedding. This limit is designed to primarily depend on blackbird's
        # internal quota based rate limiting.
        Api::RateLimitConfiguration::BLACKBIRD_TIER2_FAMILY
      end
    end
    Api::RateLimitConfiguration.for(family, self)
  end

  before do
    deliver_error! 404 if GitHub.enterprise?
    deliver_error! 404 unless logged_in?
  end

  # Semantic search.
  post "/embeddings/code/search", operation_id: :ignored do
    # NB: POST requests connect to the primary db by default, we don't want that
    ActiveRecord::Base.connected_to(role: :reading) do
      @route_owner = "@github/blackbird"
      control_access :authenticated_user,
        resource: Platform::PublicResource::new(resource: current_user),
        allow_integrations: true,
        allow_user_via_granular_actor: true

      deliver_error! 404 unless copilot_user.has_copilot_access?

      proxy_req!(:semantic)
    end
  end

  # Chunk and embed content
  post %r{/(chunks|embeddings)}, operation_id: :ignored do
    # NB: POST requests connect to the primary db by default, we don't want that
    ActiveRecord::Base.connected_to(role: :reading) do
      @route_owner = "@github/blackbird"
      control_access :authenticated_user,
        resource: Platform::PublicResource::new(resource: current_user),
        allow_integrations: true,
        allow_user_via_granular_actor: true

      deliver_error! 404 unless copilot_user.has_copilot_access?

      proxy_req!(:analysis)
    end
  end

  # Get embedding models and chunk versions
  get %r{/(chunks|embeddings).*}, operation_id: :ignored do
    @route_owner = "@github/blackbird"
    control_access :authenticated_user,
      resource: Platform::PublicResource::new(resource: current_user),
      allow_integrations: true,
      allow_user_via_granular_actor: true

    deliver_error! 404 unless copilot_user.has_copilot_access?

    proxy_req!(:analysis)
  end

  # Lexical code search
  post "/code/search", operation_id: :ignored do
    # NB: POST requests connect to the primary db by default, we don't want that
    ActiveRecord::Base.connected_to(role: :reading) do
      @route_owner = "@github/blackbird"
      control_access :authenticated_user,
        resource: Platform::PublicResource::new(resource: current_user),
        allow_integrations: true,
        allow_user_via_granular_actor: true

      deliver_error! 404 unless current_user.feature_flag_enabled?(:blackbird_code_search_api_preview, default: false)

      proxy_req!(:lexical)
    end
  end

  # Parse code to produce symbol data.
  post "/symbols", operation_id: :ignored do
    # NB: POST requests connect to the primary db by default, we don't want that
    ActiveRecord::Base.connected_to(role: :reading) do
      @route_owner = "@github/blackbird"
      control_access :authenticated_user,
        resource: Platform::PublicResource::new(resource: current_user),
        allow_integrations: true,
        allow_user_via_granular_actor: true

      proxy_req!(:analysis, include_actor: false)
    end
  end

  private

  BACKENDS = {
    lexical: {
      # NB: This is not wired up (yet). Lexical code search api
      url: GitHub.blackbird_lexical_search_url.sub("twirp", "api"),
      lab_url: GitHub.blackbird_lexical_search_lab_url.sub("twirp", "api"),
      hmac_key: GitHub.blackbird_lexical_search_hmac_key,
      proxima_url: "http://blackbird-mw-lexical.blackbird-%s.svc.cluster.local:8080/api",
    },
    analysis: {
      url: GitHub.blackbird_mw_analysis_url.sub("twirp", "api"),
      lab_url: GitHub.blackbird_mw_analysis_lab_url.sub("twirp", "api"),
      hmac_key: GitHub.blackbird_mw_analysis_hmac_key,
      proxima_url: "http://blackbird-mw-analysis.blackbird-%s.svc.cluster.local:8080/api",
    },
    semantic: {
      url: GitHub.blackbird_semantic_search_url.sub("twirp", "api"),
      lab_url: GitHub.blackbird_semantic_search_lab_url.sub("twirp", "api"),
      hmac_key: GitHub.blackbird_semantic_search_hmac_key,
      proxima_url: "http://blackbird-mw-semantic.blackbird-%s.svc.cluster.local:8080/api",
    },
  }

  # Basic idea from: https://github.com/lonre/rack-forward with modifications.
  def proxy_req!(backend, include_actor: true)
    deliver_error! 404 unless backend = BACKENDS[backend]

    url = if GitHub::Config::Proxima.current_stamp.present?
      backend[:proxima_url] % GitHub::Config::Proxima.current_stamp
    elsif current_user.feature_flag_enabled?(:blackbird_use_lab, default: false)
      backend[:lab_url] # NB: Lab only supported on the dotcom stamp
    else
      backend[:url]
    end

    req = Rack::Request.new(env)
    method = req.request_method
    uri = URI.parse("#{url}#{req.path}?#{req.query_string}")
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
    r["User-Agent"] = req.user_agent
    r["Request-HMAC"] = hmac_token(backend[:hmac_key]) unless backend[:hmac_key].blank? || GitHub::Config::Proxima.current_stamp.present?
    r["X-Forwarded-For"] = (req.env["X-Forwarded-For"].to_s.split(/, */) + [req.env["REMOTE_ADDR"]]).join(", ")
    r["X-GitHub-Api-Version"] = req.env["HTTP_X_GITHUB_API_VERSION"]
    r["X-GitHub-Base-Url"] = req.base_url
    r["X-GitHub-Request-Id"] = req.env["HTTP_X_GITHUB_REQUEST_ID"]
    r["X-GLB-Via"] = "hostname=#{GitHub.local_host_name} t=#{Time.now.to_f}"
    r["X-GitHub-Copilot-License"] = copilot_user.access_type
    r["X-GitHub-Copilot-Has-Limited-Access"] = copilot_user.has_limited_access?.to_s
    r["X-Client-Application"] = req.env["HTTP_X_CLIENT_APPLICATION"]
    r["X-Client-Source"] = req.env["HTTP_X_CLIENT_SOURCE"]
    r["X-Client-Feature"] = req.env["HTTP_X_CLIENT_FEATURE"]
    r["X-GitHub-Staff"] = "true" if current_user&.employee?

    if include_actor
      r["X-GitHub-Actor-Id"] = current_user.id
      r["X-GitHub-Actor-Access-Token"] = api_auth.token
      r["X-GitHub-Actor-Access-Token-Kind"] = BlackbirdSearch::Client::ACCESS_TOKEN_KIND_API
      r["X-GitHub-Actor-Request-Ip"] = remote_ip
      r["X-GitHub-Actor-Session-Id"] = ServerToServerTokens::Domain.hash_token(api_auth.token)

      if tenant = GitHub::CurrentTenant.get
        r["X-GitHub-Tenant"] = tenant.slug
        r["X-GitHub-Tenant-Id"] = tenant.id
        r["X-GitHub-Tenant-Shortcode"] = tenant.shortcode
      end

      experiments = {}
      if current_user.feature_flag_enabled?(:blackbird_use_voyage_3_embeddings, default: false)
        experiments["X-Experiment-Use-Voyage-3-Embeddings"] = "1"
      end
      if current_user.feature_flag_enabled?(:blackbird_clientside_indexing, default: false)
        experiments["X-Experiment-Clientside-Indexing"] = "1"
      end
      if current_user.employee?
        req.env.each do |k, v|
          next unless k.start_with?("HTTP_X_EXPERIMENT_")
          name = k.delete_prefix("HTTP_").split("_").map(&:capitalize).join("-")
          experiments[name] = v
        end
      end
      experiments.each do |k, v|
        r[k] = v
      end
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

  def copilot_user
    @copilot_user ||= Copilot::Public::User.new(current_user)
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
