# typed: true
# frozen_string_literal: true

module Api::Serializer::BillingUsageReportExport
  extend Billing::UsageDependency
  include Billing::TokenBasedBilling

  # Report type mappings from API string values to billing platform enum values
  REPORT_TYPE_MAPPING = {
    "detailed" => BillingPlatform::Api::V1::ReportType::Detailed,
    "summarized" => BillingPlatform::Api::V1::ReportType::Summarized,
    "premium_request" => BillingPlatform::Api::V1::ReportType::PremiumRequest,
    "ai_credit" => BillingPlatform::Api::V1::ReportType::PremiumRequest,
  }.freeze

  # Creates a Hash for a newly created export response.
  #
  # response    - Billing platform API response
  # report_type - String report type ("detailed", "summarized", "premium_request", "ai_credit")
  # start_date  - String start date (YYYY-MM-DD)
  # end_date    - String end date (YYYY-MM-DD)
  # actor       - User who created the export
  #
  # Returns a Hash to be serialized to JSON.
  def usage_report_export_create_hash(response, report_type:, start_date:, end_date:, actor:)
    {
      id: response[:exportOperationUuid],
      report_type: report_type,
      start_date: start_date,
      end_date: end_date,
      status: "processing",
      created_at: Time.current.utc.iso8601,
      actor: actor.display_login,
    }
  end

  # Creates a Hash for a single export response (GET /reports/:id).
  # Includes download_urls with temporary Azure SAS URLs for completed reports.
  #
  # response      - Billing platform export response
  # enterprise    - Business entity
  #
  # Returns a Hash to be serialized to JSON.
  def usage_report_export_hash(response, enterprise:)
    blob_urls = response[:downloadUrls] || []

    # Query metered exports table to get download URLs and determine status
    metered_exports = blob_urls.any? ? find_metered_exports_for_urls(blob_urls, enterprise) : []

    # Generate temporary Azure SAS URLs for direct download (only for single report requests)
    download_urls = metered_exports.any? ? metered_exports.map(&:generate_expiring_url) : []

    # Look up actor login from actor_id
    actor_login = User.find_by(id: response[:actorId])&.display_login

    build_export_hash(
      response,
      metered_exports: metered_exports,
      actor_login: actor_login,
      download_urls: download_urls,
      enterprise: enterprise
    )
  end

  # Creates a Hash for a list of exports response (GET /reports).
  # Excludes download_urls to avoid N HTTP calls to Azure for SAS URL generation.
  # Users should call GET /reports/:id to get download URLs for a specific report.
  #
  # exports       - Array of export responses from billing platform
  # enterprise    - Business entity
  #
  # Returns a Hash to be serialized to JSON.
  def usage_report_exports_list_hash(exports, enterprise:)
    # Pre-load actors to avoid N+1 queries
    actor_ids = exports.map { |export| export[:actorId] }.compact.uniq
    actors_by_id = User.where(id: actor_ids).pluck(:id, :login).to_h

    # Pre-load all metered exports in a single query to avoid N+1
    all_blob_urls = exports.flat_map { |export| export[:downloadUrls] || [] }
    metered_exports_by_filename = if all_blob_urls.any?
      find_metered_exports_for_urls(all_blob_urls, enterprise).index_by(&:filename)
    else
      {}
    end

    {
      usage_report_exports: exports.map do |export|
        # Look up metered exports for this specific export's blob URLs
        blob_urls = export[:downloadUrls] || []
        export_metered_exports = blob_urls.filter_map do |url|
          filename = extract_filename_from_url(url)
          metered_exports_by_filename[filename] if filename
        end

        build_export_hash(
          export,
          metered_exports: export_metered_exports,
          actor_login: actors_by_id[export[:actorId]],
          enterprise: enterprise
        )
      end
    }
  end

  private

  # Builds a hash representation of an export response.
  # This shared method handles the common logic for both single and list responses.
  #
  # response        - Billing platform export response
  # metered_exports - Array of Billing::MeteredUsageExport records for this export
  # actor_login     - String login of the actor who created the export
  # download_urls   - Array of download URLs, or nil to omit the field from the response
  #
  # Returns a Hash to be serialized to JSON.
  def build_export_hash(response, metered_exports:, actor_login:, download_urls: nil, enterprise: nil)
    state = response[:state]
    blob_urls = response[:downloadUrls] || []

    # Determine status based on metered exports presence
    status = if blob_urls.any?
      metered_exports.any? ? "completed" : "processing"
    else
      map_state_to_status(state)
    end

    # If this is a premium request report and TBB is enabled, override the report type to "ai_credit"
    # Only rename reports created on or after the TBB launch date; older reports retain "premium_request"
    is_premium_request = [:PremiumRequest, "premium_request", BillingPlatform::Api::V1::ReportType::PremiumRequest].include?(response[:reportType])
    report_type = if is_premium_request && enterprise && billing_tbb_enabled?(enterprise) && report_created_on_or_after_tbb_launch?(response, enterprise)
      "ai_credit"
    else
      report_type_string(response[:reportType])
    end


    # Build the base hash
    hash = {
      id: response[:exportOperationUuid],
      report_type: report_type,
      start_date: response[:startDate] ? Time.at(response[:startDate]).utc.strftime("%Y-%m-%d") : nil,
      end_date: response[:endDate] ? Time.at(response[:endDate]).utc.strftime("%Y-%m-%d") : nil,
      status: status,
      created_at: response[:createdAt] ? Time.at(response[:createdAt]).utc.iso8601 : nil,
      actor: actor_login,
    }

    # Only include download_urls when present and non-empty
    hash[:download_urls] = download_urls if download_urls.present?

    hash
  end

  def map_state_to_status(state)
    case state
    when "pending", "loading"
      "processing"
    when "completed"
      "completed"
    when "failed"
      "failed"
    else
      "processing"
    end
  end

  # Maps the report type from the billing platform response to an API string.
  # The billing platform returns report_type as a Symbol (e.g., :Summarized) in to_h,
  # not as an integer enum value.
  def report_type_string(report_type_enum)
    case report_type_enum
    when :Detailed, BillingPlatform::Api::V1::ReportType::Detailed
      "detailed"
    when :Summarized, BillingPlatform::Api::V1::ReportType::Summarized
      "summarized"
    when :PremiumRequest, BillingPlatform::Api::V1::ReportType::PremiumRequest
      "premium_request"
    when :Legacy, BillingPlatform::Api::V1::ReportType::Legacy
      "legacy"
    when :Token, BillingPlatform::Api::V1::ReportType::Token
      "token"
    else
      "detailed"
    end
  end

  # Returns whether a report was created on or after the TBB launch date.
  def report_created_on_or_after_tbb_launch?(response, enterprise)
    created_at = response[:createdAt]
    return false unless created_at

    Time.at(created_at).utc.to_date >= Billing::TokenBasedBilling::AI_CREDITS_LAUNCH_DATE
  end

  # Extracts the filename from a blob URL.
  #
  # url - String blob URL
  #
  # Returns the filename String or nil if extraction fails.
  def extract_filename_from_url(url)
    uri = URI.parse(url)
    path = uri.path
    return nil if path.blank?
    File.basename(path)
  rescue URI::InvalidURIError
    url.split("/").last
  end

  def find_metered_exports_for_urls(blob_urls, enterprise)
    return [] if blob_urls.empty?

    filenames = blob_urls.filter_map { |url| extract_filename_from_url(url) }

    Billing::MeteredUsageExport.where(
      billable_owner: enterprise,
      filename: filenames,
      is_azure_blob_storage: true
    )
  end
end
