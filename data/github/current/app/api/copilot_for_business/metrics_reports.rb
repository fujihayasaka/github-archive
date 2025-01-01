# typed: true
# frozen_string_literal: true

class Api::CopilotForBusiness::MetricsReports < Api::App
  include ReceiveSchemaWithOpenApi
  include CopilotInsightsPermissions

  REPORT_NOT_FOUND_MESSAGE = "Report not found"
  REPORT_TYPE_TO_CONTAINER_NAME = {
    enterprise_28_day: "enterprise-28-day-report",
    users_28_day: "enterprise-users-28-day"
  }.freeze

  # Azure Front Door endpoint for CDN caching of report artifacts
  # The CDN is configured with a 59-minute cache TTL
  AFD_ENDPOINT = "copilot-reports-acc0engfa5gra7ha.b01.azurefd.net".freeze

  get "/enterprises/:enterprise_id/copilot/metrics/reports/enterprise-28-day/latest", operation_id: "copilot/copilot-enterprise-usage-metrics" do
    @route_owner = "@github/copilot-metrics-reviewers"

    enterprise = find_enterprise!

    ensure_endpoint_enabled!(enterprise)

    control_access :copilot_enterprise_usage_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    ensure_enterprise_can_access_copilot_metrics_reports!(enterprise)

    receive_with_openapi

    # Get the latest 28-day enterprise metrics report
    latest_report = get_latest_28_day_report!(enterprise, :enterprise_28_day)

    deliver_raw(latest_report)
  end

  get "/enterprises/:enterprise_id/copilot/metrics/reports/users-28-day/latest", operation_id: "copilot/copilot-users-usage-metrics" do
    @route_owner = "@github/copilot-metrics-reviewers"

    enterprise = find_enterprise!

    ensure_endpoint_enabled!(enterprise)

    control_access :copilot_enterprise_usage_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: false,
      allow_integrations: false,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_ADMIN_FORBID_MESSAGE

    ensure_enterprise_can_access_copilot_metrics_reports!(enterprise)

    receive_with_openapi

    # Get the latest 28-day users metrics report
    latest_report = get_latest_28_day_report!(enterprise, :users_28_day)

    deliver_raw(latest_report)
  end

  private

  def ensure_endpoint_enabled!(enterprise)
    enabled = PermissionCheck.new(business: enterprise, user: current_user).copilot_insights_usage_metrics_api_available?
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless enabled
  end

  # Determines if we should use Azure Front Door URLs for this enterprise
  # based on the feature flag
  sig { params(enterprise: Business).returns(T::Boolean) }
  def use_afd?(enterprise)
    FeatureFlag.vexi.enabled?(:copilot_insights_azure_front_door, enterprise, default: false)
  end

  # Generates an AFD-proxied URL for a blob
  # Directly generates a SAS URL with AFD endpoint as host
  sig { params(enterprise: Business, report_export: T.untyped, blob_name: String, expires_in: ActiveSupport::Duration).returns(String) }
  def generate_afd_url_for_blob(enterprise, report_export, blob_name, expires_in)
    # Use the new method that directly generates AFD URLs
    afd_url = report_export.generate_afd_sas_url_for_blob(
      blob_name,
      expires_in: expires_in,
      content_type: "application/octet-stream",
      afd_endpoint: AFD_ENDPOINT
    )

    GitHub.logger.info(
      "Generating Azure Front Door URL for Copilot Insights report",
      "code.namespace": self.class.name,
      "code.function": "generate_afd_url_for_blob",
      "gh.enterprise.id": enterprise.id,
      "gh.copilot.afd_enabled": true,
      "gh.copilot.blob_name": blob_name,
      "gh.copilot.sas_expiry_minutes": (expires_in / 60).to_i
    )

    afd_url
  end

  sig { params(enterprise: Business).void }
  def ensure_enterprise_can_access_copilot_metrics_reports!(enterprise)
    return unless enterprise.feature_flag_enabled?(:ban_enterprise_from_copilot_metrics_reports_api, default: false)
    deliver_error!(403, message: "Your Enterprise has been temporarily blocked from this feature due to excessive downloads. Please reach out to your account manager.")
  end

  sig { params(enterprise: Business, report_type: Symbol).returns(T::Hash[Symbol, T.untyped]) }
  def get_latest_28_day_report!(enterprise, report_type)
    raise ArgumentError, "Invalid report_type: #{report_type}. Must be one of: #{REPORT_TYPE_TO_CONTAINER_NAME.keys}" unless REPORT_TYPE_TO_CONTAINER_NAME.key?(report_type)

    report_link = Copilot::MetricsReportLink.find_by(business_id: enterprise.id, report_type: report_type)

    unless report_link
      GitHub.logger.error(
        "exception.message": "Copilot::MetricsReportLink not found",
        "code.namespace": self.class.name,
        "code.function": "get_latest_28_day_report!",
        "gh.enterprise.id": enterprise.id,
        "gh.report_type": report_type,
      )
      deliver_error!(404, message: REPORT_NOT_FOUND_MESSAGE, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    end

    report_export = CopilotInsightsUsage::ReportExport.new(
      enterprise_id: enterprise.id,
      container_name: REPORT_TYPE_TO_CONTAINER_NAME[report_type]
    )

    # If AFD is enabled, we'll still use GitHub cache but store AFD URLs instead of direct SAS URLs
    if use_afd?(enterprise)
      sas_expiry = CopilotInsights::Constants::AFD_SAS_TOKEN_EXPIRY
      cache_key = "copilot_metrics_report:afd:#{enterprise.id}:#{report_link.id}:#{report_link.report_end_day}"
      cache_hit = GitHub.cache.exist?(cache_key)

      GitHub.dogstats.increment("copilot.metrics_reports.request_source",
                               tags: ["source:afd", "result:#{cache_hit ? 'hit' : 'miss'}", "report_type:#{report_type}"])

      GitHub.logger.info(
        "Using GitHub cache with AFD URLs for Copilot Insights report",
        "code.namespace": self.class.name,
        "code.function": "get_latest_28_day_report!",
        "gh.enterprise.id": enterprise.id,
        "gh.copilot.report_type": report_type,
        "gh.copilot.afd_enabled": true,
        "gh.copilot.cache_hit": cache_hit
      )

      # Get or create AFD URLs with GitHub caching
      # Use a longer TTL than the non-AFD path since AFD provides content caching
      download_urls = GitHub.cache.fetch(cache_key, ttl: CopilotInsights::Constants::AFD_CACHE_TTL, stats_key: "api.copilot.metrics_reports.#{report_type}.afd_download_urls.cache") do
        # This block only runs on a cache miss - generate new AFD URLs
        report_link.download_links.map do |blob_name|
          generate_afd_url_for_blob(enterprise, report_export, blob_name, sas_expiry)
        end
      end
    else
      # When not using AFD, use GitHub cache with a TTL slightly less than the SAS token expiry time
      # Check cache for signed links, generate and cache if not found
      cache_key = "copilot_metrics_report:enterprise:#{enterprise.id}:#{report_link.id}:#{report_link.report_end_day}"
      cache_hit = GitHub.cache.exist?(cache_key)

      # Track cache hit/miss for GitHub cache
      GitHub.dogstats.increment("copilot.metrics_reports.request_source", tags: ["source:github_cache", "result:#{cache_hit ? 'hit' : 'miss'}", "report_type:#{report_type}"])

      download_urls = GitHub.cache.fetch(cache_key, ttl: CopilotInsights::Constants::DIRECT_CACHE_TTL, stats_key: "api.copilot.metrics_reports.#{report_type}.download_urls.cache") do
        # This block only runs on a cache miss
        report_link.download_links.map do |blob_name|
          report_export.generate_sas_url_for_blob(
            blob_name,
            expires_in: CopilotInsights::Constants::DIRECT_SAS_TOKEN_EXPIRY,
            content_type: "application/octet-stream"
          )
        end
      end
    end

    # the report end date is inclusive, so we need to subtract 27 days to get the start date
    {
      download_links: download_urls,
      report_start_day: (report_link.report_end_day - 27.days).iso8601,
      report_end_day: report_link.report_end_day.iso8601,
    }
  end
end
