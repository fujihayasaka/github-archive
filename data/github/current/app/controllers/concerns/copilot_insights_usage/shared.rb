# typed: true
# frozen_string_literal: true

module CopilotInsightsUsage
  # Shared logic for Copilot Insights controllers across all contexts
  # (org, stafftools, business). Provides the MetricsKey enum, dashboard
  # fetching, and metrics extraction so every consumer speaks the same
  # type-safe language.
  module Shared
    extend T::Helpers
    extend ActiveSupport::Concern

    include ::CopilotInsightsUsage::Params

    requires_ancestor { ApplicationController }

    SPARK_USAGE_REPORT_FLAG = "copilot_metrics_use_spark_data"

    # Enum for the supported metrics key types in Copilot Insights payloads.
    # Using T::Enum ensures invalid keys are caught at type-check time.
    class MetricsKey < T::Enum
      enums do
        UsageMetrics = new(:usageMetrics)
        CodeGenerationMetrics = new(:codeGenerationMetrics)
      end
    end

    # Fetches dashboard results from the appropriate service (Spark or standard).
    #
    # @param days [Integer] number of days of data to request
    # @param spark [Boolean] whether to use the Spark data pipeline
    # @param organization [Organization, nil] the org to fetch data for
    # @param business [Business, nil] the enterprise to fetch data for
    # @return [CopilotInsightsUsage::DashboardService::Result]
    sig { params(days: Integer, spark: T::Boolean, organization: T.untyped, business: T.untyped).returns(T.untyped) }
    def fetch_copilot_dashboard_results(days:, spark:, organization: nil, business: nil)
      kwargs = { days: days }
      kwargs[:organization] = organization if organization
      kwargs[:business] = business if business

      if spark
        ::CopilotInsightsUsage::SparkDashboardService.call(**kwargs)
      else
        ::CopilotInsightsUsage::DashboardService.call(**kwargs)
      end
    end

    # Extracts the appropriate metrics hash from a dashboard result based on
    # the metrics key.
    #
    # @param metrics_key [MetricsKey] which metrics to extract
    # @param result [CopilotInsightsUsage::DashboardService::Result]
    # @return [T.untyped] the metrics data for the given key
    sig { params(metrics_key: MetricsKey, result: T.untyped).returns(T.untyped) }
    def extract_copilot_metrics(metrics_key, result)
      case metrics_key
      when MetricsKey::UsageMetrics
        result.usage_metrics
      when MetricsKey::CodeGenerationMetrics
        result.code_generation_metrics
      else
        T.absurd(metrics_key)
      end
    end

    # Maps a MetricsKey to the corresponding page_type string used in
    # export URLs and other contexts.
    sig { params(metrics_key: MetricsKey).returns(String) }
    def metrics_key_to_page_type(metrics_key)
      case metrics_key
      when MetricsKey::UsageMetrics then "usage"
      when MetricsKey::CodeGenerationMetrics then "code_generation"
      else T.absurd(metrics_key)
      end
    end

    # Returns the imported data filename from the EnterpriseReportImporter.
    # Shared across org and enterprise contexts.
    sig { returns(T.nilable(String)) }
    def imported_data_filename
      ::Copilot::Metrics::UsageReport::EnterpriseReportImporter.imported_data_filename
    end

    # Records an analytics event for the Copilot Insights page view.
    sig { params(category: String, label: String).void }
    def record_analytics_event(category:, label:)
      analytics_event(
        category: category,
        action: "show",
        label: label
      )
    end
  end
end
