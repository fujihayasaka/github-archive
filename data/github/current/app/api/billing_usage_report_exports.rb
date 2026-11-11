# typed: true
# frozen_string_literal: true

class Api::BillingUsageReportExports < Api::App
  include Billing::UsageDependency
  include Api::Serializer::BillingUsageReportExport

  # Create a new usage report export
  post "/enterprises/:enterprise_id/settings/billing/reports", operation_id: "billing/create-usage-report-export", read_from_replicas: true do
    enterprise = find_enterprise!

    # Feature flag check - return 404 if not enabled for this enterprise
    unless FeatureFlag.vexi.enabled?(:billing_api_for_csv_reports, enterprise, default: false)
      deliver_error! 404, message: "Not Found"
    end

    control_access :manage_business_billing,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Parse and validate request body
    data = receive_with_openapi

    report_type_str = data["report_type"]
    start_date_str = data["start_date"]
    # Default end_date to current day (UTC) if not provided
    end_date_str = data["end_date"].presence || Time.current.to_date.strftime("%Y-%m-%d")
    # Default send_email to false if not provided (API callers don't get emails by default)
    send_email = data["send_email"] == true

    # Get report type enum from serializer's mapping
    report_type_enum = REPORT_TYPE_MAPPING[report_type_str]

    # Parse dates (OpenAPI schema validates format)
    start_date = Date.parse(start_date_str)
    end_date = Date.parse(end_date_str)

    # Validate end_date is not in the future
    if end_date > Time.current.to_date
      deliver_error! 400, message: "end_date cannot be in the future"
    end

    # Validate start_date is not after end_date
    if start_date > end_date
      deliver_error! 400, message: "end_date must be after or equal to start_date"
    end

    # Validate date range using shared validation logic (checks max days and min start date)
    unless is_custom_range_valid?(start_date: start_date_str, end_date: end_date_str, entity: enterprise, type: report_type_enum)
      date_range_error = get_date_range_error(start_date, end_date, report_type_enum, enterprise)
      deliver_error! 400, message: date_range_error
    end

    # Call billing platform API - use UTC to avoid timezone issues
    start_timestamp = start_date.to_datetime.beginning_of_day.utc.to_i
    end_timestamp = end_date.to_datetime.end_of_day.utc.to_i

    response = billing_platform_client.request_usage_report_export(
      customer_id: enterprise.customer_id.to_s,
      start_date: start_timestamp,
      end_date: end_timestamp,
      actor_id: current_user.id,
      report_type: report_type_enum,
      send_email: send_email
    )

    if response.is_a?(Billing::Platform::Api::Error)
      handle_billing_platform_error!(response, "create usage report export")
    end

    # Emit audit log for report creation
    GitHub.instrument("billing.usage_report_create", {
      actor: current_user,
      business: enterprise,
      customer_id: enterprise.customer_id.to_s,
      report_type: report_type_str,
      start_date: start_date_str,
      end_date: end_date_str,
    })

    GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:202", "operation:billing/create-usage-report-export"])

    # Transform and deliver response using serializer
    deliver_raw usage_report_export_create_hash(response, report_type: report_type_str, start_date: start_date_str, end_date: end_date_str, actor: current_user), status: 202
  end

  # Get a usage report export by ID
  get "/enterprises/:enterprise_id/settings/billing/reports/:report_id", operation_id: "billing/get-usage-report-export" do
    enterprise = find_enterprise!

    # Feature flag check - return 404 if not enabled for this enterprise
    unless FeatureFlag.vexi.enabled?(:billing_api_for_csv_reports, enterprise, default: false)
      deliver_error! 404, message: "Not Found"
    end

    control_access :manage_business_billing,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    report_id = params[:report_id]

    # Validate UUID format
    unless valid_uuid?(report_id)
      deliver_error! 400, message: "Invalid report_id format"
    end

    # Call billing platform API
    response = billing_platform_client.get_usage_report_export(
      customer_id: enterprise.customer_id.to_s,
      export_operation_uuid: report_id
    )

    if response.is_a?(Billing::Platform::Api::Error)
      handle_billing_platform_error!(response, "get usage report export")
    end

    # Check if export was found (empty response means not found)
    if response.nil? || response.empty? || response[:exportOperationUuid].blank?
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:404", "operation:billing/get-usage-report-export"])
      deliver_error! 404, message: "Usage report export not found"
    end

    GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/get-usage-report-export"])

    # Transform response using serializer
    deliver_raw usage_report_export_hash(response, enterprise: enterprise)
  end

  # List usage report exports
  get "/enterprises/:enterprise_id/settings/billing/reports", operation_id: "billing/list-usage-report-exports" do
    enterprise = find_enterprise!

    # Feature flag check - return 404 if not enabled for this enterprise
    unless FeatureFlag.vexi.enabled?(:billing_api_for_csv_reports, enterprise, default: false)
      deliver_error! 404, message: "Not Found"
    end

    control_access :manage_business_billing,
      resource: enterprise,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # Call billing platform API
    response = billing_platform_client.get_usage_report_exports(
      customer_id: enterprise.customer_id.to_s
    )

    if response.is_a?(Billing::Platform::Api::Error)
      handle_billing_platform_error!(response, "list usage report exports")
    end

    GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:200", "operation:billing/list-usage-report-exports"])

    # Transform and deliver response using serializer (handles N+1 prevention internally)
    deliver_raw usage_report_exports_list_hash(response[:exports] || [], enterprise: enterprise)
  end

  private

  def billing_platform_client
    Billing::Platform::Api::Client.new
  end

  # Get a descriptive error message for date range validation failures
  def get_date_range_error(start_date, end_date, report_type_enum, enterprise)
    if end_date < start_date
      return "end_date must be after or equal to start_date"
    end

    days_in_range = (end_date - start_date).to_i + 1
    max_days = case report_type_enum
    when USAGE_REPORT_DETAILED_TYPE
      MAX_DETAILED_REPORT_DAYS
    when USAGE_REPORT_SUMMARIZED_TYPE
      MAX_SUMMARIZED_REPORT_DAYS
    when USAGE_REPORT_PREMIUM_REQUEST_TYPE
      MAX_PREMIUM_REQUEST_REPORT_DAYS
    end

    if days_in_range > max_days
      report_type_str = REPORT_TYPE_MAPPING.key(report_type_enum)
      return "Date range exceeds maximum of #{max_days} days for #{report_type_str} reports"
    end

    min_start = min_custom_date(customer: T.must(enterprise.customer))
    if start_date < min_start
      return "start_date cannot be earlier than #{min_start.strftime('%Y-%m-%d')}"
    end

    if end_date > Time.current.to_date
      return "end_date cannot be in the future"
    end

    "Invalid date range"
  end

  def valid_uuid?(string)
    return false if string.blank?
    /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.match?(string)
  end

  def handle_billing_platform_error!(error, operation)
    if error.already_exists?
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:409", "operation:billing/#{operation.parameterize}"])
      deliver_error! 409, message: "A usage report export is already in progress"
    elsif error.http_4xx?
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:#{error.http_status}", "operation:billing/#{operation.parameterize}"])
      deliver_error! error.http_status, message: error.message
    else
      # Note: The billing platform client already reports 5xx errors to Failbot
      GitHub.dogstats.increment("billing_platform.api.status", tags: ["status:503", "operation:billing/#{operation.parameterize}"])
      deliver_error! 503, message: "Unable to #{operation}. Please try again later."
    end
  end
end
