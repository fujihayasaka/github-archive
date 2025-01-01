# typed: false
# frozen_string_literal: true

require "monolith-twirp-insights-sql"
require "json"

module InsightsHelper

  # This state is for errors with getting the state
  ERROR_STATE = "error"

  # These states are with errors internal to insights
  # registering the organization to insights
  ERROR_ONBOARDING_STATE = "error_onboarding"
  # marking the organization as 100% ready to use
  ERROR_READY_STATE = "error_ready"

  # This is the state that insights is 100% ready to use for the organization
  READY_STATE = "ready"
  # This is the state that the organization has not been onboarded to insights
  NOT_FOUND_STATE = "not_found"

  # This is the state that the organization has been added but not started importing
  REQUESTED_STATE = "requested"
  # This is the state that the organization has been added and started importing
  ONBOARDING_STATE = "onboarding"

  # This is the state that the organization has asked to be removed from insights, they have 48hours to change their mind before deleting
  OFF_STATE = "off"

  # This is the state that the organization is being removed from insights.
  DELETING_STATE = "deleting"

  # This is the state that the organization is has been removed from insights.
  DELETED_STATE = "deleted"

  # This is the only enterprise id allowed on constant staging/develop (legal and security constraints) and is the only development enterprise id
  INSIGHTS_DEVELOPMENT_BUSINESS_ID = 11468

  def markdown_embed_token_for(scope:, data:)
    GitHub::Authentication::SignedAuthToken::Session.generate(
      session: user_session,
      scope: scope,
      expires: 5.minutes.from_now,
      data: data,
    )
  end

  def markdown_embed_scope_for(object)
    "markdown_embed_token:#{object&.class}/#{object&.id}"
  end

  def add_insights_csp_exceptions
    SecureHeaders.append_content_security_policy_directives(request, connect_src: connect_src_exceptions)
  end

  def connect_src_exceptions
    servers = [GitHub.insights_api_server_endpoint]
    servers << GitHub.insights_staging_api_server_endpoint if current_user&.employee?
    servers
  end

  def hmac_header
    key = ENV.fetch("INSIGHTS_HMAC_KEY", "insightshmac")
    GitHub::RequestHmacValidator.request_hmac(Time.current, key)
  end

  def insights_get_headers
    {
      "Content-Type" => "application/json",
      "Request-HMAC" => hmac_header,
      "accept" => "application/json"
    }
  end

  def staging_cookie_override
    defined?(current_user) && current_user&.employee? && defined?(request) && request.cookies["target_insights_staging_env"].present? && request.cookies["target_insights_staging_env"] == "true"
  end

  def insights_api_server_endpoint
    return GitHub.insights_staging_api_server_endpoint if staging_cookie_override
    GitHub.insights_api_server_endpoint
  end

  # this returns the state, definitions and constants above
  def insights_get_feature_state(org_id)
    state = ERROR_STATE

    begin
      response = insights_call_feature_state(org_id)
      if response.status == 200
        result = JSON.parse(response.body)
        state = result.fetch("state")
        errors = result.fetch("errors")
        if errors.fetch("hasErrors")
          error_reason = errors.fetch("errorMessage")
        end
      else
        error_reason = "Status code: #{response.status}"
      end
    rescue JSON::ParserError
      error_reason = "Bad Body: " + response.body
    rescue Faraday::Error => err
      error_reason = "Faraday error: " + err.message
    end

    [state, error_reason]
  end

  def insights_call_feature_state(org_id)
    conn = Faraday.new(url: insights_api_server_endpoint, headers: insights_get_headers) do |faraday|
      faraday.use(GitHub::FaradayMiddleware::RequestID)
      faraday.adapter Faraday.default_adapter
    end

    conn.get("/manager/state/#{org_id}")
  end
end
