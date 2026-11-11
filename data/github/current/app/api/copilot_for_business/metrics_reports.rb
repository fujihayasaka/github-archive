# typed: true
# frozen_string_literal: true

class Api::CopilotForBusiness::MetricsReports < Api::App
  include ReceiveSchemaWithOpenApi

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

    ensure_entity_can_access_copilot_metrics_reports!(enterprise)

    receive_with_openapi

    # Get the latest 28-day enterprise metrics report
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

    instrument_copilot_metrics_api_analytics(entity: enterprise, report_type: :enterprise_28_day)

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

    ensure_entity_can_access_copilot_metrics_reports!(enterprise)

    receive_with_openapi

    # Get the latest 28-day users metrics report
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

    instrument_copilot_metrics_api_analytics(entity: enterprise, report_type: :enterprise_users_28_day)

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

    ensure_entity_can_access_copilot_metrics_reports!(enterprise)

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

    instrument_copilot_metrics_api_analytics(entity: enterprise, report_type: :enterprise_1_day)

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

    ensure_entity_can_access_copilot_metrics_reports!(enterprise)

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

    instrument_copilot_metrics_api_analytics(entity: enterprise, report_type: :enterprise_users_1_day)

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
      forbid_message: Copilot::ORGANIZATION_INSUFFICIENT_PERMISSIONS_MESSAGE

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

    instrument_copilot_metrics_api_analytics(entity: organization, report_type: :organization_28_day)

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
      forbid_message: Copilot::ORGANIZATION_INSUFFICIENT_PERMISSIONS_MESSAGE

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

    instrument_copilot_metrics_api_analytics(entity: organization, report_type: :organization_users_28_day)

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
      forbid_message: Copilot::ORGANIZATION_INSUFFICIENT_PERMISSIONS_MESSAGE

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
      if resp.status == 204
        instrument_copilot_metrics_api_analytics(entity: organization, report_type: :organization_1_day)
        halt deliver_empty(status: 204)
      end

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

    instrument_copilot_metrics_api_analytics(entity: organization, report_type: :organization_1_day)

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
      forbid_message: Copilot::ORGANIZATION_INSUFFICIENT_PERMISSIONS_MESSAGE

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
      if resp.status == 204
        instrument_copilot_metrics_api_analytics(entity: organization, report_type: :organization_users_1_day)
        halt deliver_empty(status: 204)
      end

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

    instrument_copilot_metrics_api_analytics(entity: organization, report_type: :organization_users_1_day)

    deliver_raw(report_data)
  end

  # GET /enterprises/{enterprise}/copilot/metrics/reports/user-teams-1-day?day=2026-02-26
  get "/enterprises/:enterprise_id/copilot/metrics/reports/user-teams-1-day", operation_id: "copilot/copilot-enterprise-user-teams-one-day-report" do
    @route_owner = "@github/copilot-metrics-reviewers"
    enterprise = find_enterprise!

    ensure_membership!(enterprise)
    ensure_enterprise_user_teams_endpoint_enabled!(enterprise)

    control_access :enterprise_copilot_metrics,
      resource: enterprise,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ENTERPRISE_METRICS_INSUFFICIENT_PERMISSIONS_MESSAGE

    ensure_entity_can_access_copilot_metrics_reports!(enterprise)

    receive_with_openapi

    day = params[:day]
    # Ensure the requested day is within the last 1 year
    requested_date = Date.parse(day) rescue nil
    if requested_date.nil? || requested_date < 1.year.ago.to_date || requested_date > Date.today
      GitHub.logger.info(
        "Invalid day parameter for enterprise user-teams 1-day Copilot Metrics Report",
        "code.namespace": self.class.name,
        "gh.enterprise.id": enterprise.id,
        "gh.requested_day": day,
      )

      deliver_error!(400, message: "Invalid day parameter. Expected format: YYYY-MM-DD (e.g., 2025-10-10). Date must be within the last year and not in the future.", documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    end

    # Get the 1-day enterprise user-teams metrics report for the requested day from Copilot Usage Service
    client = copilot_usage_service_client
    path = "/enterprises/#{enterprise.id}/copilot/metrics/reports/user-teams-1-day"
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
            "code.function": "enterprise-user-teams-1-day",
            "gh.enterprise.id": enterprise.id,
            "gh.enterprise.slug": enterprise.slug,
            "gh.copilot.report_type": "enterprise_user_teams_1_day",
            "exception.class": e.class.name,
            "exception.message": e.message,
          )
        end
      end
    else
      GitHub.logger.error(
        "Failed to fetch enterprise user-teams 1-day Copilot Metrics Report from Copilot Usage Service",
        "code.namespace": self.class.name,
        "gh.enterprise.id": enterprise.id,
        "gh.requested_day": day,
        "gh.http.status": resp.status,
        "gh.response.body": resp.body
      )

      deliver_error!(resp.status, message: resp.body)
    end

    instrument_copilot_metrics_api_analytics(entity: enterprise, report_type: :enterprise_user_teams_1_day)

    deliver_raw(report_data)
  end

  # GET /organizations/{organization}/copilot/metrics/reports/user-teams-1-day?day=2026-02-26
  get "/organizations/:organization_id/copilot/metrics/reports/user-teams-1-day", operation_id: "copilot/copilot-organization-user-teams-one-day-report" do
    @route_owner = "@github/copilot-metrics-reviewers"
    organization = find_org!

    ensure_membership!(organization)
    ensure_organization_user_teams_endpoint_enabled!(organization)

    control_access :organization_copilot_metrics,
      resource: organization,
      allow_user_via_granular_actor: true,
      allow_integrations: true,
      forbid: true,
      forbid_message: Copilot::ORGANIZATION_INSUFFICIENT_PERMISSIONS_MESSAGE

    ensure_entity_can_access_copilot_metrics_reports!(organization)

    receive_with_openapi

    day = params[:day]
    # Ensure the requested day is within the last 1 year
    requested_date = Date.parse(day) rescue nil
    if requested_date.nil? || requested_date < 1.year.ago.to_date || requested_date > Date.today
      GitHub.logger.info(
        "Invalid day parameter for organization user-teams 1-day Copilot Metrics Report",
        "code.namespace": self.class.name,
        "gh.organization.id": organization.id,
        "gh.requested_day": day,
      )

      deliver_error!(400, message: "Invalid day parameter. Expected format: YYYY-MM-DD (e.g., 2025-10-10). Date must be within the last year and not in the future.", documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    end

    # Get the 1-day organization user-teams metrics report for the requested day from Copilot Usage Service
    client = copilot_usage_service_client
    path = "/organizations/#{organization.id}/copilot/metrics/reports/user-teams-1-day"
    resp = client.connection.get(path, { day: day })

    if resp.success?
      if resp.status == 204
        instrument_copilot_metrics_api_analytics(entity: organization, report_type: :organization_user_teams_1_day)
        halt deliver_empty(status: 204)
      end

      report_data = resp.body
      if report_data.is_a?(String)
        begin
          parsed = GitHub::JSON.parse(report_data)
          report_data = parsed if parsed.is_a?(Hash)
        rescue StandardError => e
          GitHub.logger.warn(
            "copilot.metrics_reports.json_parse_failed",
            "code.namespace": self.class.name,
            "code.function": "organization-user-teams-1-day",
            "gh.organization.id": organization.id,
            "gh.organization.slug": organization.slug,
            "gh.copilot.report_type": "organization-user-teams-1-day-report",
            "exception.class": e.class.name,
            "exception.message": e.message,
          )
        end
      end
    else
      GitHub.logger.error(
        "Failed to fetch organization user-teams 1-day Copilot Metrics Report from Copilot Usage Service",
        "code.namespace": self.class.name,
        "gh.organization.id": organization.id,
        "gh.requested_day": day,
        "gh.http.status": resp.status,
        "gh.response.body": resp.body
      )

      deliver_error!(resp.status, message: resp.body)
    end

    instrument_copilot_metrics_api_analytics(entity: organization, report_type: :organization_user_teams_1_day)

    deliver_raw(report_data)
  end

  private

  def ensure_membership!(entity)
    return if current_integration.present?  # Server-to-server GitHub App
    return if current_user_programmatic_access.present?  # User-to-server GitHub App - let control_access handle it
    return if entity.readable_by?(current_user)
    return if entity.is_a?(::Business) && entity.supports_unaffiliated_user_accounts? && entity.unaffiliated_member?(current_user)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
  end

  def ensure_endpoint_enabled!(enterprise)
    permission_check = CopilotInsightsPermissions::PermissionCheck.new(business: enterprise, user: current_user)

    unless permission_check.copilot_insights_supported_env? && !FeatureFlag.vexi.enabled?(:copilot_metrics_blocklist, enterprise, default: false)
      deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    end

    opted_in = permission_check.opted_in?
    deliver_error!(403, message: "Copilot insights must be enabled to access both enterprise-level and user-level data.") unless opted_in
  end

  def ensure_1_day_endpoint_enabled!(enterprise)
    api_enabled = CopilotInsightsPermissions::PermissionCheck.new(business: enterprise, user: current_user).copilot_insights_usage_metrics_api_available?

    feature_flag_enabled = FeatureFlag.vexi.enabled?(:copilot_insights_enterprise_1_day_report, enterprise, default: false)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless api_enabled && feature_flag_enabled
  end

  def ensure_organization_endpoint_enabled!(organization)
    permission = CopilotInsightsPermissions::PermissionCheck.new(organization: organization, user: current_user)
    api_enabled = permission.copilot_insights_usage_metrics_org_api_available?

    if !permission.copilot_insights_supported_env?
      deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    elsif !api_enabled
      deliver_error!(403, message: "The 'Copilot usage metrics' policy must be enabled to use this API", documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/copilot/concepts/copilot-metrics#organization-level-metrics")
    end
  end

  def ensure_enterprise_user_teams_endpoint_enabled!(enterprise)
    api_enabled = CopilotInsightsPermissions::PermissionCheck.new(business: enterprise, user: current_user).copilot_insights_usage_metrics_api_available?

    feature_flag_enabled = FeatureFlag.vexi.enabled?(:copilot_insights_user_teams_1_day_report, enterprise, default: false)
    deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest") unless api_enabled && feature_flag_enabled
  end

  def ensure_organization_user_teams_endpoint_enabled!(organization)
    permission = CopilotInsightsPermissions::PermissionCheck.new(organization: organization, user: current_user)
    api_enabled = permission.copilot_insights_usage_metrics_org_api_available?

    feature_flag_enabled = FeatureFlag.vexi.enabled?(:copilot_insights_user_teams_1_day_report, organization, default: false)

    if !permission.copilot_insights_supported_env?
      deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    elsif !api_enabled
      deliver_error!(403, message: "The 'Copilot usage metrics' policy must be enabled to use this API", documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/copilot/concepts/copilot-metrics#organization-level-metrics")
    elsif !feature_flag_enabled
      deliver_error!(404, documentation_url: "#{GitHub::Config::DOCS_BASE_URL}/rest")
    end
  end

  sig { params(entity: T.any(Business, Organization)).void }
  def ensure_entity_can_access_copilot_metrics_reports!(entity)
    return unless entity.feature_flag_enabled?(:ban_enterprise_from_copilot_metrics_reports_api, default: false)

    entity_type = entity.is_a?(Business) ? "Enterprise" : "Organization"
    deliver_error!(403, message: "Your #{entity_type} has been temporarily blocked from this feature due to excessive downloads. Please reach out to your account manager. For more on scraping GitHub and how it may affect your rights, please review our Terms of Service (https://docs.github.com/en/site-policy/github-terms/github-terms-of-service).")
  end

  def instrument_copilot_metrics_api_analytics(entity:, report_type:)
    entity_id_label = entity.is_a?(Business) ? "business_id:#{entity.id}" : "organization_id:#{entity.id}"
    entity_slug_label = entity.is_a?(Business) ? "business_slug:#{entity.slug}" : "organization_slug:#{entity.display_login}"
    GlobalInstrumenter.instrument("analytics.event",
      actor: current_user,
      category: "copilot_metrics_reports_api",
      action: report_type.to_s,
      label: "source:rest_api;report_type:#{report_type};#{entity_slug_label};#{entity_id_label}"
    )
  end

  def copilot_usage_service_client
    CopilotInsightsUsage::CopilotUsageServiceClient.new
  end
end
