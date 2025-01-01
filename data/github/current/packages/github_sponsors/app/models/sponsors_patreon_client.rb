# typed: strict
# frozen_string_literal: true

class SponsorsPatreonClient
  class Error < StandardError; end
  class UnauthorizedError < StandardError; end

  BASE_PATREON_URL = "https://www.patreon.com"
  PATREON_API_PATH = "/api/oauth2"
  REDIRECT_URL = T.let("#{GitHub.url}/sponsors/accounts/patreon", String)
  PAGE_CURSOR_PARAM = "page[cursor]" # https://docs.patreon.com/#pagination-and-sorting
  DEFAULT_MAX_PAGES = 5
  DATADOG_PREFIX = "sponsors.patreon_client"

  # https://docs.patreon.com/#scopes
  # Includes scopes necessary for sponsors and maintainers since a given GitHub user could play both roles and
  # we only have a single SponsorsPatreonUser record for them:
  SCOPES = "identity identity[email] campaigns w:campaigns.webhook campaigns.members"

  # Request URI to authenticate as sponsor with Patreon
  #
  # state - Optional String used as session/user identification after redirection from Patreon
  #
  # Returns String
  sig { params(state: String).returns(String) }
  def self.auth_url_for_sponsor(state:)
    auth_url(auth_params(state: state, scope: SCOPES))
  end

  # Request URI to authenticate as maintainer with Patreon
  #
  # state - Optional String used as session/user identification after redirection from Patreon
  #
  # Returns String
  sig { params(state: String).returns(String) }
  def self.auth_url_for_sponsorable(state:)
    auth_url(auth_params(state: state, scope: SCOPES))
  end

  sig { params(campaign_id: String, state: String, min_cents: Integer).returns(String) }
  def self.become_patreon_url(campaign_id:, state:, min_cents:)
    build_become_patreon_url(become_patreon_params(campaign_id: campaign_id, state: state, min_cents: min_cents))
  end

  sig { params(code: String).returns(T::Hash[String, T.any(String, Integer)]) }
  def self.get_token(code)
    # https://docs.patreon.com/#step-4-validating-receipt-of-the-oauth-token
    response = connection.post("#{PATREON_API_PATH}/token") do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        grant_type: "authorization_code",
        code: code,
        client_id: GitHub.patreon_client_id,
        client_secret: GitHub.patreon_client_secret,
        redirect_uri: REDIRECT_URL,
      )
    end
    response.body
  rescue Faraday::Error => err
    raise_for_error_response(err, prefix: "Error getting token: ")
  end

  sig { params(refresh_token: String).returns(T::Hash[String, T.any(String, Integer)]) }
  def self.refresh_token(refresh_token)
    # https://docs.patreon.com/#step-7-keeping-up-to-date
    response = connection.post("#{PATREON_API_PATH}/token") do |req|
      req.headers["Content-Type"] = "application/x-www-form-urlencoded"
      req.body = URI.encode_www_form(
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        client_id: GitHub.patreon_client_id,
        client_secret: GitHub.patreon_client_secret,
      )
    end
    response.body
  rescue Faraday::Error => err
    raise_for_error_response(err, prefix: "Error refreshing token: ")
  end

  sig { params(err: Faraday::Error, prefix: T.nilable(String)).void }
  def self.raise_for_error_response(err, prefix: nil)
    response = err.response || {}
    message = error_message_from_json(response[:body] || {})
    status = response[:status]
    error_class = status == 401 ? UnauthorizedError : Error
    prefix ||= "#{status} error: "
    raise error_class.new("#{prefix}#{message.presence || err}")
  end

  sig do
    params(
      block: T.nilable(T.proc.params(conn: Faraday::Connection).returns(Faraday::Connection))
    ).returns(Faraday::Connection)
  end
  def self.connection(&block)
    GitHub::FaradayClient::External.new(BASE_PATREON_URL) do |conn|
      conn.response :raise_error
      conn.response :json, content_type: /\bjson\z/
      conn.headers["User-Agent"] = user_agent
      conn.adapter Faraday.default_adapter
      yield(conn) if block_given?
    end
  end

  sig { returns(String) }
  def self.user_agent
    if GitHub::AppEnvironment.production?
      "GitHub Sponsors"
    else
      "GitHub Sponsors test"
    end
  end

  sig { params(json: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
  def self.error_message_from_json(json)
    if json["errors"].present?
      json["errors"].map { |e| e["detail"] }.to_sentence
    elsif json["error"].present?
      json["error"]
    end
  end

  sig { params(access_token: String, refresh_token: String).void }
  def initialize(access_token:, refresh_token:)
    @access_token = access_token
    @refresh_token = refresh_token
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def get_identity
    # https://docs.patreon.com/#get-api-oauth2-v2-identity
    get("/v2/identity", params: {
      "include" => "campaign", # campaign for maintainers
      "fields[user]" => "full_name,email",
      "fields[campaign]" => "vanity,published_at",
    })
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def get_campaigns
    # https://docs.patreon.com/#get-api-oauth2-v2-campaigns
    get("/v2/campaigns", params: {
      "include" => "tiers",
      "fields[campaign]" => "is_monthly,published_at",
      "fields[tier]" => "amount_cents,published",
    })
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def get_monthly_campaigns
    result = get_campaigns
    campaigns = result.dig("data") || []
    monthly_campaigns = campaigns.select { |campaign| campaign.dig("attributes", "is_monthly") }
    included_tier_data_by_tier_id = (result.dig("included") || [])
      .select { |included_data| included_data["type"] == "tier" }
      .map { |tier| [tier["id"], tier] }
      .to_h
    monthly_campaigns.map do |campaign|
      campaign["relationships"]["tiers"]["data"] = campaign["relationships"]["tiers"]["data"].map do |tier_data|
        tier_data.merge(included_tier_data_by_tier_id[tier_data["id"]])
      end
      campaign
    end
  end

  # Public: Load Patreon memberships for a campaign.
  #
  # campaign_id - Patreon campaign ID whose memberships should be loaded
  # params - optional query parameters for the Patreon API request
  # max_pages - optional number of pages to load; defaults to 5 if unspecified
  sig do
    params(
      campaign_id: String,
      params: T::Hash[String, String],
      max_pages: T.nilable(Integer)
    ).returns(SponsorsPatreonMemberships)
  end
  def get_memberships(campaign_id, params: {}, max_pages: nil)
    max_pages ||= DEFAULT_MAX_PAGES
    is_first_batch = params[PAGE_CURSOR_PARAM].blank?
    datadog_tags = ["max_pages:#{max_pages}", "first_batch:#{is_first_batch}"]

    result = GitHub.dogstats.time("#{DATADOG_PREFIX}.get_memberships", tags: datadog_tags) do
      # https://docs.patreon.com/#get-api-oauth2-v2-campaigns-campaign_id-members
      get_all_pages("/v2/campaigns/#{campaign_id}/members", params: params.merge(
        "include" => "currently_entitled_tiers,user",
        "fields[member]" => "patron_status,currently_entitled_amount_cents,pledge_cadence",
      ), max_pages: max_pages)
    end

    SponsorsPatreonMemberships.new(memberships: result["data"], next_cursor: next_page_cursor_for(result))
  end

  # Public: Load active Patreon memberships for a campaign.
  #
  # campaign_id - Patreon campaign ID whose memberships should be loaded
  # params - optional query parameters for the Patreon API request
  # max_pages - optional number of pages to load; defaults to 5 if unspecified
  sig do
    params(
      campaign_id: String,
      params: T::Hash[String, String],
      max_pages: T.nilable(Integer)
    ).returns(SponsorsPatreonUsersAndAmounts)
  end
  def get_active_membership_cents_by_patron_patreon_user_id(campaign_id, params: {}, max_pages: nil)
    memberships_result = get_memberships(campaign_id, params: params, max_pages: max_pages)

    # Don't rely on the patron_status field to determine whose membership is active, since that can go to
    # declined_patron temporarily due to a payment error, then go back to active_patron later, which would cause
    # churn on our end.
    active_memberships = memberships_result.memberships.select do |membership|
      current_entitled_cents = membership.dig("attributes", "currently_entitled_amount_cents")
      current_entitled_cents.present? && current_entitled_cents > 0
    end

    patreon_user_ids_and_amounts = active_memberships.each_with_object({}) do |membership, result|
      # Number of months between charges, e.g. 1 (for a monthly membership) or 12 (for an annual membership)
      pledge_cadence = membership.dig("attributes", "pledge_cadence") || 1
      currently_entitled_amount_cents = membership.dig("attributes", "currently_entitled_amount_cents") || 0
      # Decimal amount per month, e.g. 1672 cents ($16.72) / 12 months = 139.333...
      monthly_amount = BigDecimal(currently_entitled_amount_cents) / BigDecimal(pledge_cadence)
      # Formatted monthly amount in cents, e.g. 139.333... -> 139 ($1.39/mo for a $16.72/year pledge)
      monthly_amount_in_cents = Billing::Money.new(monthly_amount).cents
      patron_patreon_user_id = membership.dig("relationships", "user", "data", "id")

      result[patron_patreon_user_id] ||= 0
      result[patron_patreon_user_id] += monthly_amount_in_cents
    end

    SponsorsPatreonUsersAndAmounts.new(amount_in_cents_by_patreon_user_id: patreon_user_ids_and_amounts,
      next_cursor: memberships_result.next_cursor)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def get_webhooks
    # https://docs.patreon.com/#get-api-oauth2-v2-webhooks
    get("/v2/webhooks", params: {
      "include" => "campaign",
      "fields[campaign]" => "is_monthly",
    })
  end

  sig { params(triggers: T::Array[String], campaign_id: String, uri: String).returns(T::Hash[String, T.untyped]) }
  def create_webhook(triggers:, campaign_id:, uri:)
    # https://docs.patreon.com/#post-api-oauth2-v2-webhooks
    post("/v2/webhooks", params: {
      data: {
        type: "webhook",
        attributes: { triggers: triggers, uri: uri },
        relationships: { campaign: { data: { type: "campaign", id: campaign_id } } },
      }
    })
  end

  sig { params(webhook_id: String).void }
  def delete_webhook(webhook_id)
    # https://github.com/github/sponsors/issues/5278
    delete("/v2/webhooks/#{webhook_id}")
  end

  private

  sig { params(path: String, params: T::Hash[String, String]).returns(T.untyped) }
  def get(path, params: {})
    response = connection.get("#{PATREON_API_PATH}#{path}", params)
    response.body
  rescue Faraday::Error => err
    self.class.raise_for_error_response(err)
  end

  sig { params(path: String, params: T::Hash[String, String]).returns(T.untyped) }
  def post(path, params: {})
    response = connection.post("#{PATREON_API_PATH}#{path}") do |req|
      if params.present?
        req.body = params.to_json
        req.headers["Content-Type"] = "application/json"
      end
    end
    response.body
  rescue Faraday::Error => err
    self.class.raise_for_error_response(err)
  end

  sig { params(path: String).returns(T.untyped) }
  def delete(path)
    response = connection.delete("#{PATREON_API_PATH}#{path}")
    response.body
  rescue Faraday::Error => err
    self.class.raise_for_error_response(err)
  end

  sig do
    params(
      path: String,
      params: T::Hash[String, String],
      page: Integer,
      max_pages: T.nilable(Integer),
    ).returns(T.untyped)
  end
  def get_all_pages(path, params: {}, page: 1, max_pages: nil)
    current_page = get(path, params: params)
    max_pages ||= DEFAULT_MAX_PAGES
    return current_page if page >= max_pages # more pages of results than we want to load

    next_cursor = T.let(next_page_cursor_for(current_page), T.nilable(String))
    combined_pages = current_page

    while next_cursor.present? && page < max_pages
      next_page = get_next_page(path, cursor: next_cursor, params: params)
      combined_pages = combine_pages(combined_pages, next_page)
      page += 1
      next_cursor = next_page_cursor_for(next_page)
    end

    combined_pages
  end

  sig do
    params(page1: T::Hash[String, T.untyped], page2: T::Hash[String, T.untyped]).returns(T::Hash[String, T.untyped])
  end
  def combine_pages(page1, page2)
    non_meta_keys = page1.keys - ["meta"]
    combined_pages = T.unsafe(page1).slice(*non_meta_keys).merge("meta" => page2["meta"])

    non_meta_keys.each do |key|
      if page2.key?(key)
        if combined_pages[key].respond_to?(:concat)
          combined_pages[key].concat(page2[key])
        elsif combined_pages[key].respond_to?(:merge)
          combined_pages[key].merge!(page2[key])
        end
      end
    end

    combined_pages
  end

  sig { params(page: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
  def next_page_cursor_for(page)
    return unless page.respond_to?(:key) # not a hash
    page.dig("meta", "pagination", "cursors", "next")
  end

  sig { params(path: String, cursor: String, params: T::Hash[String, String]).returns(T.untyped) }
  def get_next_page(path, cursor:, params: {})
    next_page = get(path, params: params.merge(PAGE_CURSOR_PARAM => cursor))
    raise Error.new("Unexpected pagination response") unless next_page.respond_to?(:key?)
    next_page
  end

  sig { returns(Faraday::Connection) }
  def connection
    self.class.connection do |conn|
      conn.headers["Authorization"] = "Bearer #{@access_token}"
    end
  end

  # https://docs.patreon.com/#step-2-making-the-log-in-button
  sig { params(state: String, scope: String).returns(String) }
  def self.auth_params(state:, scope:)
    {
      response_type: "code",
      client_id: GitHub.patreon_client_id,
      redirect_uri: REDIRECT_URL,
      scope: scope,
      state: state,
    }.to_param
  end
  private_class_method :auth_params

  sig { params(params: String).returns(String) }
  def self.auth_url(params)
    "https://www.patreon.com/oauth2/authorize?" + params
  end
  private_class_method :auth_url

  sig { params(campaign_id: String, state: String, min_cents: Integer).returns(String) }
  def self.become_patreon_params(campaign_id:, state:, min_cents: 0)
    {
      response_type: "code",
      campaign_id: campaign_id,
      min_cents: min_cents,
      client_id: GitHub.patreon_client_id,
      scope: SCOPES,
      state: state,
      redirect_uri: REDIRECT_URL,
    }.to_param
  end
  private_class_method :become_patreon_params

  sig { params(params: String).returns(String) }
  def self.build_become_patreon_url(params)
    "https://www.patreon.com/oauth2/become-patron?" + params
  end
  private_class_method :build_become_patreon_url
end
