# typed: strict
# frozen_string_literal: true

require "resolv"
require "ipaddr"

class Businesses::AiControls::McpPrivateServersController < Businesses::BusinessController
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include Businesses::CopilotShared
  include Businesses::AiControls::McpPrivateServersFeatureFlag

  javascript_bundle :copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Billing,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot

  layout "layouts/react_business"

  DEFAULT_PAGE_SIZE = 10
  FETCH_OPEN_TIMEOUT_SECONDS = 2
  FETCH_TIMEOUT_SECONDS = 5
  MAX_RESPONSE_BODY_SIZE = T.let(512 * 1024, Integer) # 512KB

  allow_verified_fetch only: [:index, :fetch_server_json]

  before_action :ensure_not_standalone_copilot_business
  before_action :ai_controls_enabled?
  before_action :ensure_trial_business_is_dfd_trial_or_contains_cfb_trial, only: [:index]
  before_action :handle_ai_controls_trial_entry_flow, only: [:index]
  before_action :ai_controls_read_required
  before_action :ensure_private_servers_feature_flag_enabled
  before_action :ai_controls_write_required, only: [:new, :edit]

  sig { void }
  def index
    render "businesses/ai_controls/mcp/private_servers", locals: {
      business: this_business,
      can_write: this_business&.actor_can_write_enterprise_ai_controls?(current_user) || false,
      is_admin: this_business&.adminable_by?(current_user) || false,
      title: "Private MCP servers",
      per_page: DEFAULT_PAGE_SIZE,
      servers: sample_servers,
    }
  end

  sig { void }
  def new
    render "businesses/ai_controls/mcp/private_server_form", locals: {
      business: this_business,
      title: "Create private server",
      server: nil,
      save_label: "Publish",
      raw_json_value: params[:server_json].to_s,
    }
  end

  sig { void }
  def edit
    server = sample_servers.find { |s| s[:id] == params[:id].to_i }
    if server.nil?
      render_404
      return
    end

    render "businesses/ai_controls/mcp/private_server_form", locals: {
      business: this_business,
      title: "Edit private server",
      server: server,
      save_label: "Republish",
    }
  end

  sig { void }
  def fetch_server_json # rubocop:todo GitHub/UseRestfulActions
    raw_url = params[:url].to_s
    if raw_url.blank?
      render json: { error: "URL is required" }, status: :unprocessable_entity
      return
    end

    uri = parse_http_uri(raw_url)
    if uri.nil?
      render json: { error: "Invalid URL. Use a full https:// URL pointing to a public host." }, status: :unprocessable_entity
      return
    end

    response = external_json_fetch_client(uri).get(uri.request_uri) do |request|
      request.headers["Accept"] = "application/json"
    end

    unless response.success?
      render json: { error: "Unable to fetch JSON (#{response.status})" }, status: :unprocessable_entity
      return
    end

    body_size = response.body.to_s.bytesize
    if body_size > MAX_RESPONSE_BODY_SIZE
      render json: { error: "Response too large (max #{MAX_RESPONSE_BODY_SIZE / 1024}KB)." }, status: :unprocessable_entity
      return
    end

    payload = parse_json_object(response.body)
    if payload.nil?
      render json: { error: "URL did not return a valid JSON object." }, status: :unprocessable_entity
    else
      render json: payload, status: :ok
    end
  rescue Faraday::Error
    render json: { error: "Unable to load server JSON from URL." }, status: :unprocessable_entity
  end

  private

  sig { params(raw_url: String).returns(T.nilable(URI::HTTPS)) }
  def parse_http_uri(raw_url)
    uri = URI.parse(raw_url)
    return nil unless uri.is_a?(URI::HTTPS)

    host = uri.host
    return nil if host.blank?
    # Defense-in-depth: the egress proxy (GitHub.external_communication_proxy_host) provides
    # primary SSRF protection by pinning DNS at the network layer. This application-layer check
    # adds an additional guard but cannot fully prevent DNS rebinding (TOCTOU between resolve
    # and connect). The proxy makes rebinding attacks ineffective in production.
    return nil if resolved_to_private_address?(host)

    uri
  rescue URI::InvalidURIError
    nil
  end

  PRIVATE_IP_RANGES = T.let([
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("::1/128"),
    IPAddr.new("fe80::/10"),
    IPAddr.new("fc00::/7"),
  ].freeze, T::Array[IPAddr])

  sig { params(host: String).returns(T::Boolean) }
  def resolved_to_private_address?(host)
    addresses = Resolv.getaddresses(host)
    return true if addresses.empty?

    addresses.any? do |addr|
      ip = IPAddr.new(addr)
      PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end
  rescue Resolv::ResolvError
    true
  end

  sig { params(raw: T.untyped).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def parse_json_object(raw)
    parsed = JSON.parse(raw.to_s)
    return nil unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError
    nil
  end

  sig { params(uri: URI::HTTPS).returns(Faraday::Connection) }
  def external_json_fetch_client(uri)
    port = uri.port
    default_port = uri.default_port
    base_url = "#{uri.scheme}://#{uri.host}"
    base_url += ":#{port}" if port.present? && default_port != port

    GitHub::FaradayClient.external(
      "mcp_private_servers_fetch_server_json",
      base_url,
      request: {
        open_timeout: FETCH_OPEN_TIMEOUT_SECONDS,
        timeout: FETCH_TIMEOUT_SECONDS,
      },
    )
  end

  sig { override.returns(String) }
  def ai_controls_section_title
    "Private MCP servers"
  end

  sig { override.returns(Symbol) }
  def ai_controls_selected_link
    :businesses_ai_controls_mcp
  end

  sig { void }
  def ai_controls_enabled?
    render_404 unless helpers.show_ai_controls?(this_business)
  end

  sig { void }
  def ai_controls_read_required
    render_404 unless this_business&.actor_can_read_enterprise_ai_controls?(current_user)
  end

  sig { void }
  def ai_controls_write_required
    render_404 unless this_business&.actor_can_write_enterprise_ai_controls?(current_user)
  end

  sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def sample_servers
    [
      {
        id: 1,
        name: "acme-corp/internal-search",
        version: "2.4.0",
        replacement_link: "",
        updated_at: 2.hours.ago,
        updated_by: { "login" => "octocat", "avatar_url" => "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" },
        allowlist_count: 2,
      },
      {
        id: 2,
        name: "acme-corp/analytics-proxy",
        version: "1.9.2",
        replacement_link: "acme-corp/analytics-proxy-v2",
        updated_at: 1.day.ago,
        updated_by: { "login" => "hubot", "avatar_url" => "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" },
        allowlist_count: 1,
      },
      {
        id: 3,
        name: "acme-corp/knowledge-gateway",
        version: "3.1.0",
        replacement_link: "",
        updated_at: 3.days.ago,
        updated_by: { "login" => "monalisa", "avatar_url" => "https://github.githubassets.com/images/modules/logos_page/GitHub-Mark.png" },
        allowlist_count: 0,
      },
    ]
  end
end
