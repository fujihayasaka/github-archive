# typed: true
# frozen_string_literal: true

class Api::CopilotForBusiness::Usage < Api::Enterprise::App
  get "/enterprises/:enterprise_id/copilot/usage-records", operation_id: "copilot/get-usage-records" do
    ActiveRecord::Base.connected_to(role: :reading) do
      current_enterprise = find_enterprise!

      deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless current_enterprise.feature_flag_enabled?(:copilot_api_enable_usage_record_telemetry, default: false)

      usage_permission = if current_enterprise.feature_flag_enabled?(:copilot_usage_records_read_enterprise_scope, default: false)
        :read_enterprise_copilot_usage
      else
        :read_enterprise_audit_logs
      end

      control_access :standard_authorization,
        resource: current_enterprise,
        permission: usage_permission,
        forbid: true,
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        enforce_oauth_app_policy: true

      receive_with_openapi

      # Extract & validate params
      phrase = params[:phrase] || ""
      per_page = (params[:per_page] || 100).to_i
      per_page = [[per_page, 1].max, 100].min
      direction = (params[:order] || "desc").upcase

      # Call driftwood
      query = GitHub.driftwood_client_v1.copilot_usage_query(
        enterprise_id: current_enterprise.id,
        phrase: phrase,
        per_page: per_page,
        after: params[:after] || "",
        before: params[:before] || "",
        direction: direction
      )

      results = query.execute

      # Pagination (Link headers)
      if results.has_next_page?
        @links.add_current({ after: results.after_cursor, before: "" }, rel: "next")
      end
      if results.has_previous_page?
        @links.add_current({ after: "", before: "" }, rel: "first")
        @links.add_current({ after: "", before: results.before_cursor }, rel: "prev")
      end

      deliver_raw(results.results, status: 200)
    rescue Driftwood::TwirpUtil::InvalidArgumentError
      deliver_error!(400, message: "The supplied query is invalid")
    rescue Driftwood::TwirpUtil::RateLimitedError
      deliver_error!(429, message: "Please try again later.")
    rescue Driftwood::TwirpUtil::Error, Faraday::Error, Twirp::Error
      deliver_error!(502, message: "Upstream service unavailable")
    end
  end

  private

  # Once this feature flag has been rolled out, this method can be deleted and instead add
  # rate_limit_as Api::RateLimitConfiguration::COPILOT_USAGE_RECORDS_FAMILY to the top of this class as
  # recommended here: https://github.com/github/api-gateway/blob/main/docs/rate-limit-configuration.md#adding-a-new-family-to-the-rest-api
  def rate_limit_configuration
    return super unless FeatureFlag.vexi.enabled?(:api_copilot_usage_records_rate_limit, current_user, default: false)
    Api::RateLimitConfiguration.for(Api::RateLimitConfiguration::COPILOT_USAGE_RECORDS_FAMILY, self)
  end

  # Expected response for rate limited requests is 429: https://github.com/github/agent-control-plane/issues/540.
  # Also for reference: https://tools.ietf.org/html/rfc6585#section-4.
  # Only override to 429 when the lower rate limit family is active otherwise, fall back to the default.
  def rate_limit_status_code
    return super unless FeatureFlag.vexi.enabled?(:api_copilot_usage_records_rate_limit, current_user, default: false)
    429
  end
end
