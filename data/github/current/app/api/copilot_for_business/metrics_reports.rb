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

    ensure_membership!(enterprise)
    ensure_endpoint_enabled!(enterprise)

    control_access :enterprise_copilot_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_METRICS_INSUFFICIENT_PERMISSIONS_MESSAGE

    if FeatureFlag.vexi.enabled?(:org_metrics_report_for_monolith, enterprise, default: false)
      ensure_entity_can_access_copilot_metrics_reports!(enterprise)
    else
      ensure_enterprise_can_access_copilot_metrics_reports!(enterprise)
    end

    receive_with_openapi

    # Get the latest 28-day enterprise metrics report
    if FeatureFlag.vexi.enabled?(:use_copilot_usage_service_for_copilot_metrics_report_links, enterprise, default: false)
      client = copilot_usage_service_client
      path = "/enterprises/#{enterprise.id}/copilot/metrics/reports/enterprise-28-day/latest"
      resp = client.connection.get(path)

      if resp.success?
        latest_report = resp.body
        # Copilot Usage Service returns a JSON object. Ensure we are not double-encoding by
        # parsing string bodies into Ruby objects before handing to deliver_raw.
        if latest_report.is_a?(String)
          begin
            parsed = GitHub::JSON.parse(latest_report)
            # Only replace when the top-level shape is an object (Hash). Arrays or primitives
            # are unexpected here; keep original in those cases.
            latest_report = parsed if parsed.is_a?(Hash)
          rescue StandardError => e
            GitHub.logger.warn(
              "copilot.metrics_reports.json_parse_failed",
              "code.namespace": self.class.name,
              "code.function": "enterprise-28-day-latest",
              "gh.enterprise.id": enterprise.id,
              "gh.enterprise.slug": enterprise.slug,
              "gh.copilot.report_type": "enterprise_28_day",
              "exception.class": e.class.name,
              "exception.message": e.message,
            )
          end
        end
      else
        deliver_error!(resp.status, message: resp.body)
      end
    else
      latest_report = get_latest_28_day_report!(enterprise, :enterprise_28_day)
    end

    deliver_raw(latest_report)
  end

  get "/enterprises/:enterprise_id/copilot/metrics/reports/users-28-day/latest", operation_id: "copilot/copilot-users-usage-metrics" do
    @route_owner = "@github/copilot-metrics-reviewers"

    enterprise = find_enterprise!

    ensure_membership!(enterprise)
    ensure_endpoint_enabled!(enterprise)

    control_access :enterprise_copilot_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_METRICS_INSUFFICIENT_PERMISSIONS_MESSAGE

    if FeatureFlag.vexi.enabled?(:org_metrics_report_for_monolith, enterprise, default: false)
      ensure_entity_can_access_copilot_metrics_reports!(enterprise)
    else
      ensure_enterprise_can_access_copilot_metrics_reports!(enterprise)
    end

    receive_with_openapi

    # Get the latest 28-day users metrics report
    if FeatureFlag.vexi.enabled?(:use_copilot_usage_service_for_copilot_metrics_report_links, enterprise, default: false)
      client = copilot_usage_service_client
      path = "/enterprises/#{enterprise.id}/copilot/metrics/reports/users-28-day/latest"
      resp = client.connection.get(path)

      if resp.success?
        latest_report = resp.body
        if latest_report.is_a?(String)
          begin
            parsed = GitHub::JSON.parse(latest_report)
            latest_report = parsed if parsed.is_a?(Hash)
          rescue StandardError => e
            GitHub.logger.warn(
              "copilot.metrics_reports.json_parse_failed",
              "code.namespace": self.class.name,
              "code.function": "users-28-day-latest",
              "gh.enterprise.id": enterprise.id,
              "gh.enterprise.slug": enterprise.slug,
              "gh.copilot.report_type": "users_28_day",
              "exception.class": e.class.name,
              "exception.message": e.message,
            )
          end
        end
      else
        deliver_error!(resp.status, message: resp.body)
      end
    else
      latest_report = get_latest_28_day_report!(enterprise, :users_28_day)
    end

    deliver_raw(latest_report)
  end

  # GET /enterprise/{enterprise}/copilot/metrics/reports/enterprise-1-day?day=2025-07-31
  get "/enterprises/:enterprise_id/copilot/metrics/reports/enterprise-1-day", operation_id: "copilot/copilot-enterprise-one-day-usage-metrics" do
    @route_owner = "@github/copilot-metrics-reviewers"
    enterprise = find_enterprise!

    ensure_membership!(enterprise)
    ensure_1_day_endpoint_enabled!(enterprise)

    control_access :enterprise_copilot_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_METRICS_INSUFFICIENT_PERMISSIONS_MESSAGE

    if FeatureFlag.vexi.enabled?(:org_metrics_report_for_monolith, enterprise, default: false)
      ensure_entity_can_access_copilot_metrics_reports!(enterprise)
    else
      ensure_enterprise_can_access_copilot_metrics_reports!(enterprise)
    end

    receive_with_openapi

    day = params[:day]
    # Ensure the requested day is within the last 1 year
    requested_date = Date.parse(day) rescue nil
    if requested_date.nil? || requested_date < 1.year.ago.to_date || requested_date > Date.today
      GitHub.logger.info(
        "Invalid day parameter for enterprise 1-day Copilot Metrics Report",
        "code.namespace": self.class.name,
        "gh.enterprise.id": enterprise.id,
        "gh.requested_day": day,
      )

      deliver_error!(400, message: "Invalid day parameter. Expected format: YYYY-MM-DD (e.g., 2025-10-10). Date must be within the last year and not in the future.", documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    end

    # Get the 1-day enterprise metrics report for the requested day from Copilot Usage Service
    client = copilot_usage_service_client
    path = "/enterprises/#{enterprise.id}/copilot/metrics/reports/enterprise-1-day"
    resp = client.connection.get(path, { day: day })

    if resp.success?
      report_data = resp.body
      if report_data.is_a?(String)
        begin
          parsed = GitHub::JSON.parse(report_data)
          report_data = parsed if parsed.is_a?(Hash)
        rescue StandardError => e
          GitHub.logger.warn(
            "copilot.metrics_reports.json_parse_failed",
            "code.namespace": self.class.name,
            "code.function": "enterprise-1-day",
            "gh.enterprise.id": enterprise.id,
            "gh.enterprise.slug": enterprise.slug,
            "gh.copilot.report_type": "enterprise_1_day",
            "exception.class": e.class.name,
            "exception.message": e.message,
          )
        end
      end
    else
      GitHub.logger.error(
        "Failed to fetch enterprise 1-day Copilot Metrics Report from Copilot Usage Service",
        "code.namespace": self.class.name,
        "gh.enterprise.id": enterprise.id,
        "gh.requested_day": day,
        "gh.http.status": resp.status,
        "gh.response.body": resp.body
      )

      deliver_error!(resp.status, message: resp.body)
    end

    deliver_raw(report_data)
  end

  # GET /enterprise/{enterprise}/copilot/metrics/reports/users-1-day?day=2025-07-31
  get "/enterprises/:enterprise_id/copilot/metrics/reports/users-1-day", operation_id: "copilot/copilot-users-one-day-usage-metrics" do
    @route_owner = "@github/copilot-metrics-reviewers"
    enterprise = find_enterprise!

    ensure_membership!(enterprise)
    ensure_1_day_endpoint_enabled!(enterprise)

    control_access :enterprise_copilot_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_METRICS_INSUFFICIENT_PERMISSIONS_MESSAGE

    if FeatureFlag.vexi.enabled?(:org_metrics_report_for_monolith, enterprise, default: false)
      ensure_entity_can_access_copilot_metrics_reports!(enterprise)
    else
      ensure_enterprise_can_access_copilot_metrics_reports!(enterprise)
    end

    receive_with_openapi

    day = params[:day]
    # Ensure the requested day is within the last 1 year
    requested_date = Date.parse(day) rescue nil
    if requested_date.nil? || requested_date < 1.year.ago.to_date || requested_date > Date.today
      GitHub.logger.info(
        "Invalid day parameter for users 1-day Copilot Metrics Report",
        "code.namespace": self.class.name,
        "gh.enterprise.id": enterprise.id,
        "gh.requested_day": day,
      )

      deliver_error!(400, message: "Invalid day parameter. Expected format: YYYY-MM-DD (e.g., 2025-10-10). Date must be within the last year and not in the future.", documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    end

    # Get the 1-day enterprise metrics report for the requested day from Copilot Usage Service
    client = copilot_usage_service_client
    path = "/enterprises/#{enterprise.id}/copilot/metrics/reports/users-1-day"
    resp = client.connection.get(path, { day: day })

    if resp.success?
      report_data = resp.body
      if report_data.is_a?(String)
        begin
          parsed = GitHub::JSON.parse(report_data)
          report_data = parsed if parsed.is_a?(Hash)
        rescue StandardError => e
          GitHub.logger.warn(
            "copilot.metrics_reports.json_parse_failed",
            "code.namespace": self.class.name,
            "code.function": "users-1-day",
            "gh.enterprise.id": enterprise.id,
            "gh.enterprise.slug": enterprise.slug,
            "gh.copilot.report_type": "users_1_day",
            "exception.class": e.class.name,
            "exception.message": e.message,
          )
        end
      end
    else
      GitHub.logger.error(
        "Failed to fetch users 1-day Copilot Metrics Report from Copilot Usage Service",
        "code.namespace": self.class.name,
        "gh.enterprise.id": enterprise.id,
        "gh.requested_day": day,
        "gh.http.status": resp.status,
        "gh.response.body": resp.body
      )

      deliver_error!(resp.status, message: resp.body)
    end

    deliver_raw(report_data)
  end

  # GET /organizations/{organization}/copilot/metrics/reports/organization-28-day/latest
  get "/organizations/:organization_id/copilot/metrics/reports/organization-28-day/latest", operation_id: "copilot/copilot-organization-usage-metrics" do
    @route_owner = "@github/copilot-metrics-reviewers"

    organization = find_org!

    ensure_membership!(organization)
    ensure_organization_endpoint_enabled!(organization)

    control_access :organization_copilot_metrics,
      resource: organization,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ORGANIZATION_METRICS_INSUFFICIENT_PERMISSIONS_MESSAGE

    ensure_entity_can_access_copilot_metrics_reports!(organization)

    receive_with_openapi

    # Get the latest 28-day organization metrics report
    client = copilot_usage_service_client
    path = "/organizations/#{organization.id}/copilot/metrics/reports/organization-28-day/latest"
    resp = client.connection.get(path)

    if resp.success?
      latest_report = resp.body
      # Copilot Usage Service returns a JSON object. Ensure we are not double-encoding by
      # parsing string bodies into Ruby objects before handing to deliver_raw.
      if latest_report.is_a?(String)
        begin
          parsed = GitHub::JSON.parse(latest_report)
          # Only replace when the top-level shape is an object (Hash). Arrays or primitives
          # are unexpected here; keep original in those cases.
          latest_report = parsed if parsed.is_a?(Hash)
        rescue StandardError => e
          GitHub.logger.warn(
            "copilot.metrics_reports.json_parse_failed",
            "code.namespace": self.class.name,
            "code.function": "organization-28-day-latest",
            "gh.organization.id": organization.id,
            "gh.organization.slug": organization.slug,
            "gh.copilot.report_type": "organization-28-day-report",
            "exception.class": e.class.name,
            "exception.message": e.message,
          )
        end
      end
    else
      deliver_error!(resp.status, message: resp.body)
    end

    deliver_raw(latest_report)
  end

  # GET /organizations/{organization}/copilot/metrics/reports/users-28-day/latest
  get "/organizations/:organization_id/copilot/metrics/reports/users-28-day/latest", operation_id: "copilot/copilot-organization-users-usage-metrics" do
    @route_owner = "@github/copilot-metrics-reviewers"

    organization = find_org!

    ensure_membership!(organization)
    ensure_organization_endpoint_enabled!(organization)

    control_access :organization_copilot_metrics,
      resource: organization,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ORGANIZATION_METRICS_INSUFFICIENT_PERMISSIONS_MESSAGE

    ensure_entity_can_access_copilot_metrics_reports!(organization)

    receive_with_openapi

    # Get the latest 28-day users metrics report
    client = copilot_usage_service_client
    path = "/organizations/#{organization.id}/copilot/metrics/reports/users-28-day/latest"
    resp = client.connection.get(path)

    if resp.success?
      latest_report = resp.body
      if latest_report.is_a?(String)
        begin
          parsed = GitHub::JSON.parse(latest_report)
          latest_report = parsed if parsed.is_a?(Hash)
        rescue StandardError => e
          GitHub.logger.warn(
            "copilot.metrics_reports.json_parse_failed",
            "code.namespace": self.class.name,
            "code.function": "users-28-day-latest",
            "gh.organization.id": organization.id,
            "gh.organization.slug": organization.slug,
            "gh.copilot.report_type": "organization-users-28-day-report",
            "exception.class": e.class.name,
            "exception.message": e.message,
          )
        end
      end
    else
      deliver_error!(resp.status, message: resp.body)
    end

    deliver_raw(latest_report)
  end

  # GET /organizations/{organization}/copilot/metrics/reports/organization-1-day?day=2025-07-31
  get "/organizations/:organization_id/copilot/metrics/reports/organization-1-day", operation_id: "copilot/copilot-organization-one-day-usage-metrics" do
    @route_owner = "@github/copilot-metrics-reviewers"
    organization = find_org!

    ensure_membership!(organization)
    ensure_organization_endpoint_enabled!(organization)

    control_access :organization_copilot_metrics,
      resource: organization,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ORGANIZATION_METRICS_INSUFFICIENT_PERMISSIONS_MESSAGE

    ensure_entity_can_access_copilot_metrics_reports!(organization)

    receive_with_openapi

    day = params[:day]
    # Ensure the requested day is within the last 1 year
    requested_date = Date.parse(day) rescue nil
    if requested_date.nil? || requested_date < 1.year.ago.to_date || requested_date > Date.today
      GitHub.logger.info(
        "Invalid day parameter for organization 1-day Copilot Metrics Report",
        "code.namespace": self.class.name,
        "gh.organization.id": organization.id,
        "gh.requested_day": day,
      )

      deliver_error!(400, message: "Invalid day parameter. Expected format: YYYY-MM-DD (e.g., 2025-10-10). Date must be within the last year and not in the future.", documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    end

    # Get the 1-day organization metrics report for the requested day from Copilot Usage Service
    client = copilot_usage_service_client
    path = "/organizations/#{organization.id}/copilot/metrics/reports/organization-1-day"
    resp = client.connection.get(path, { day: day })

    if resp.success?
      report_data = resp.body
      if report_data.is_a?(String)
        begin
          parsed = GitHub::JSON.parse(report_data)
          report_data = parsed if parsed.is_a?(Hash)
        rescue StandardError => e
          GitHub.logger.warn(
            "copilot.metrics_reports.json_parse_failed",
            "code.namespace": self.class.name,
            "code.function": "organization-1-day",
            "gh.organization.id": organization.id,
            "gh.organization.slug": organization.slug,
            "gh.copilot.report_type": "organization-1-day-report",
            "exception.class": e.class.name,
            "exception.message": e.message,
          )
        end
      end
    else
      GitHub.logger.error(
        "Failed to fetch organization 1-day Copilot Metrics Report from Copilot Usage Service",
        "code.namespace": self.class.name,
        "gh.organization.id": organization.id,
        "gh.requested_day": day,
        "gh.http.status": resp.status,
        "gh.response.body": resp.body
      )

      deliver_error!(resp.status, message: resp.body)
    end

    deliver_raw(report_data)
  end

  # GET /organizations/{organization}/copilot/metrics/reports/users-1-day?day=2025-07-31
  get "/organizations/:organization_id/copilot/metrics/reports/users-1-day", operation_id: "copilot/copilot-organization-users-one-day-usage-metrics" do
    @route_owner = "@github/copilot-metrics-reviewers"
    organization = find_org!

    ensure_membership!(organization)
    ensure_organization_endpoint_enabled!(organization)

    control_access :organization_copilot_metrics,
      resource: organization,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ORGANIZATION_METRICS_INSUFFICIENT_PERMISSIONS_MESSAGE

    ensure_entity_can_access_copilot_metrics_reports!(organization)

    receive_with_openapi

    day = params[:day]
    # Ensure the requested day is within the last 1 year
    requested_date = Date.parse(day) rescue nil
    if requested_date.nil? || requested_date < 1.year.ago.to_date || requested_date > Date.today
      GitHub.logger.info(
        "Invalid day parameter for users 1-day Copilot Metrics Report",
        "code.namespace": self.class.name,
        "gh.organization.id": organization.id,
        "gh.requested_day": day,
      )

      deliver_error!(400, message: "Invalid day parameter. Expected format: YYYY-MM-DD (e.g., 2025-10-10). Date must be within the last year and not in the future.", documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    end

    # Get the 1-day organization metrics report for the requested day from Copilot Usage Service
    client = copilot_usage_service_client
    path = "/organizations/#{organization.id}/copilot/metrics/reports/users-1-day"
    resp = client.connection.get(path, { day: day })

    if resp.success?
      report_data = resp.body
      if report_data.is_a?(String)
        begin
          parsed = GitHub::JSON.parse(report_data)
          report_data = parsed if parsed.is_a?(Hash)
        rescue StandardError => e
          GitHub.logger.warn(
            "copilot.metrics_reports.json_parse_failed",
            "code.namespace": self.class.name,
            "code.function": "users-1-day",
            "gh.organization.id": organization.id,
            "gh.organization.slug": organization.slug,
            "gh.copilot.report_type": "organization-users-1-day-report",
            "exception.class": e.class.name,
            "exception.message": e.message,
          )
        end
      end
    else
      GitHub.logger.error(
        "Failed to fetch users 1-day Copilot Metrics Report from Copilot Usage Service",
        "code.namespace": self.class.name,
        "gh.organization.id": organization.id,
        "gh.requested_day": day,
        "gh.http.status": resp.status,
        "gh.response.body": resp.body
      )

      deliver_error!(resp.status, message: resp.body)
    end

    deliver_raw(report_data)
  end

  private

  def ensure_membership!(entity)
    return if current_integration.present?  # Server-to-server GitHub App
    return if FeatureFlag.vexi.enabled?(:org_metrics_report_for_monolith, entity, default: false) && current_user_programmatic_access.present?  # User-to-server GitHub App - let control_access handle it
    return if entity.readable_by?(current_user)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
  end

  def ensure_endpoint_enabled!(enterprise)
    permission_check = PermissionCheck.new(business: enterprise, user: current_user)
    return if permission_check.copilot_insights_usage_metrics_api_available?

    public_preview_enabled = FeatureFlag.vexi.enabled?(:copilot_insights_public_preview, enterprise, default: false)

    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless public_preview_enabled

    if public_preview_enabled
      opted_in = permission_check.opted_in?
      deliver_error!(403, message: "Copilot insights must be enabled to access both enterprise-level and user-level data.") unless opted_in
    end
  end

  def ensure_1_day_endpoint_enabled!(enterprise)
    api_enabled = PermissionCheck.new(business: enterprise, user: current_user).copilot_insights_usage_metrics_api_available?

    feature_flag_enabled = FeatureFlag.vexi.enabled?(:copilot_insights_enterprise_1_day_report, enterprise, default: false)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless api_enabled && feature_flag_enabled
  end

  def ensure_organization_endpoint_enabled!(organization)
    api_enabled = PermissionCheck.new(organization: organization, user: current_user).copilot_insights_usage_metrics_org_api_available?

    org_metrics_api_enabled = FeatureFlag.vexi.enabled?(:org_metrics_report_for_monolith, organization, default: false)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless api_enabled && org_metrics_api_enabled
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
    deliver_error!(403, message: "Your Enterprise has been temporarily blocked from this feature due to excessive downloads. Please reach out to your account manager. For more on scraping GitHub and how it may affect your rights, please review our Terms of Service (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).")
  end

  sig { params(entity: T.any(Business, Organization)).void }
  def ensure_entity_can_access_copilot_metrics_reports!(entity)
    return unless entity.feature_flag_enabled?(:ban_enterprise_from_copilot_metrics_reports_api, default: false)

    entity_type = entity.is_a?(Business) ? "Enterprise" : "Organization"
    deliver_error!(403, message: "Your #{entity_type} has been temporarily blocked from this feature due to excessive downloads. Please reach out to your account manager. For more on scraping GitHub and how it may affect your rights, please review our Terms of Service (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).")
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

  def copilot_usage_service_client
    CopilotInsightsUsage::CopilotUsageServiceClient.new
  end
end
