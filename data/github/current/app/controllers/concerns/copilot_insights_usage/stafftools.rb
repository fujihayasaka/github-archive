# typed: true
# frozen_string_literal: true

require "react_payload"

module CopilotInsightsUsage
  module Stafftools
    extend T::Helpers
    extend ActiveSupport::Concern

    include ::CopilotInsightsUsage::Shared

    requires_ancestor { StafftoolsController }

    def ensure_usage_dashboard_entity_supported
      return if this_user.organization?

      render_404
    end

    private

    def get_export_files_from_usage_service(path, report_prefix, entity_id:, entity_type:)
      client = CopilotInsightsUsage::CopilotUsageServiceClient.new
      resp = client.connection.get(path)

      if !resp.success?
        # On 404, return empty data as the report is not available yet
        if resp.status == 404
          GitHub.logger.info(
            "No report available from Copilot Usage Service (404)",
            "code.namespace": self.class.name,
            "gh.#{entity_type}.id": entity_id,
            "gh.request.path": path
          )
          return []
        end

        # For other errors, log and raise
        GitHub.logger.error(
          "Failed to fetch export files from Copilot Usage Service",
          "code.namespace": self.class.name,
          "gh.#{entity_type}.id": entity_id,
          "gh.http.status": resp.status,
          "gh.response.body": resp.body,
          "gh.request.path": path
        )
        raise "Failed to fetch export files from Copilot Usage Service: #{resp.status} #{resp.body}"
      end

      latest_report = resp.body

      # Parse JSON string responses like the API controller does
      if latest_report.is_a?(String)
        begin
          parsed = GitHub::JSON.parse(latest_report)
          latest_report = parsed if parsed.is_a?(Hash)
        rescue StandardError => e
          GitHub.logger.error(
            "Failed to parse JSON response from Copilot Usage Service",
            "code.namespace": self.class.name,
            "gh.#{entity_type}.id": entity_id,
            "exception.class": e.class.name,
            "exception.message": e.message,
            "gh.request.path": path
          )
          raise "Failed to parse JSON response from Copilot Usage Service: #{e.message}"
        end
      end

      # Convert download_links to the expected format for the view
      if latest_report.is_a?(Hash) && latest_report["download_links"].is_a?(Array)
        latest_report["download_links"].map.with_index do |url, index|
          {
            "name" => "#{report_prefix}_#{index + 1}",
            "url" => url
          }
        end
      else
        []
      end
    end

    sig { params(spark: T::Boolean).returns(T.untyped) }
    def fetch_stafftools_dashboard_results(spark:)
      fetch_copilot_dashboard_results(organization: this_user, days: days, spark: spark)
    end

    sig do
      params(
        route_id: String,
        metrics_key: Shared::MetricsKey,
        export_files_url: String,
        spark: T::Boolean
      ).returns(CopilotInsights::Payload)
    end
    def build_stafftools_copilot_insights_payload(route_id:, metrics_key:, export_files_url:, spark:)
      result = fetch_stafftools_dashboard_results(spark: spark)
      metrics = extract_copilot_metrics(metrics_key, result)
      display_flags = result.display_flags

      CopilotInsights::Payload.new(
        route_id: route_id,
        metrics_key: metrics_key,
        metrics: metrics,
        copilot_license_management_link: stafftools_user_path(this_user),
        export_files_url: export_files_url,
        display_flags: {
          blankslate: display_flags.fetch(:blankslate, false),
          error: display_flags.fetch(:error, false),
          no_matching_results: display_flags.fetch(:no_matching_results, false),
        },
        copilot_disabled: !::Copilot::Organization.new(this_user).copilot_enabled?,
        slug: this_user.display_login,
        canonical_query_params: @canonical_params,
      )
    end

  end
end
