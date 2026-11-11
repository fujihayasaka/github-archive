# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module InsightsExport
      extend T::Helpers
      include GitHub::Memoizer
      include Copilot::Metrics
      include Copilot::Helpers

      SPARK_USAGE_REPORT_FLAG = "copilot_metrics_use_spark_data"

      abstract!

      # Generate export files for copilot insights usage data
      sig { params(business: ::Business, report_class: T.class_of(Copilot::Metrics::UsageReport)).returns(T::Array[T::Hash[String, String]]) }
      def generate_export_files(business, report_class: Copilot::Metrics::UsageReport)
        if GitHub::AppEnvironment.production? || GitHub::AppEnvironment.test?
          spark_usage_report_enabled = FeatureFlag.vexi.enabled?(SPARK_USAGE_REPORT_FLAG, business, default: false)
          effective_report_class = spark_usage_report_enabled ? Copilot::Metrics::SparkUsageReport : report_class

          usage_report = effective_report_class.new(enterprise_id: business.id)

          latest_date = usage_report.get_latest_date

          if latest_date.nil?
            []
          else
            report_export =
              if effective_report_class == Copilot::Metrics::SparkUsageReport
                CopilotInsightsUsage::ReportExport.new(
                  enterprise: business,
                  date: latest_date,
                  tenant_id: GitHub.copilot_metrics_spark_spn_tenant_id,
                  client_id: GitHub.copilot_metrics_spark_spn_client_id,
                  client_secret: GitHub.copilot_metrics_spark_spn_client_secret,
                  storage_account_name: GitHub.copilot_metrics_spark_storage_account_name,
                  use_spark_etl_path: true
                )
              else
                CopilotInsightsUsage::ReportExport.new(enterprise: business, date: latest_date)
              end

            export_files = report_export.urls

            if export_files.empty?
              GitHub.logger.info(
                "Copilot Insights export_files empty",
                "code.namespace": "Copilot::Businesses::InsightsExport",
                "code.function": "generate_export_files",
                "gh.enterprise.id": business.id,
                "gh.copilot.export.latest_date": latest_date.iso8601,
                "gh.copilot.export.report_class": effective_report_class.name,
                "gh.copilot.export.spark_enabled": spark_usage_report_enabled,
                "gh.copilot.export.prefix": report_export.prefix,
              )
            end

            export_files
          end
        else
          # In development, return sample file URLs
          [
            { "name" => "testFile1.ndjson", "url" => "https://example.com/testFile.ndjson" },
            { "name" => "testFile2.ndjson", "url" => "https://example.com/testFile2.ndjson" },
          ]
        end
      end
    end
  end
end
