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
    CUS_DASHBOARD_FLAG = "copilot_dashboard_use_cus_api"

    # Enum for the supported metrics key types in Copilot Insights payloads.
    # Using T::Enum ensures invalid keys are caught at type-check time.
    class MetricsKey < T::Enum
      enums do
        UsageMetrics = new(:usageMetrics)
        CodeGenerationMetrics = new(:codeGenerationMetrics)
        ImpactMetrics = new(:impactMetrics)
      end
    end

    # Returns whether the CUS API path is enabled for the given entity.
    # Defaults to false; gated by the copilot_dashboard_use_cus_api flag.
    # When true, dashboard reads go through CUS HTTP endpoints.
    sig { params(entity: T.untyped).returns(T::Boolean) }
    def cus_dashboard_enabled?(entity)
      return false unless entity
      FeatureFlag.vexi.enabled?(CUS_DASHBOARD_FLAG, entity, default: false)
    end

    # Fetches dashboard results from the appropriate service.
    #
    # Priority order:
    # 1. CUS API (copilot_dashboard_use_cus_api flag)
    # 2. Spark Kusto (copilot_metrics_use_spark_data flag)
    # 3. Standard Kusto (default)
    #
    # @param days [Integer] number of days of data to request
    # @param spark [Boolean] whether to use the Spark data pipeline
    # @param organization [Organization, nil] the org to fetch data for
    # @param business [Business, nil] the enterprise to fetch data for
    # @return [CopilotInsightsUsage::DashboardService::Result]
    sig { params(days: Integer, spark: T::Boolean, cus: T::Boolean, organization: T.untyped, business: T.untyped).returns(T.untyped) }
    def fetch_copilot_dashboard_results(days:, spark:, cus: false, organization: nil, business: nil)
      kwargs = { days: days }
      kwargs[:organization] = organization if organization
      kwargs[:business] = business if business

      GitHub.logger.info(
        "Copilot Insights dashboard data source selected",
        "code.namespace": "CopilotInsightsUsage::Shared",
        "code.function": "fetch_copilot_dashboard_results",
        "gh.copilot_insights.data_source": cus ? "cus" : "kusto",
        "gh.copilot_insights.entity_type": organization ? "organization" : "business",
        "gh.copilot_insights.entity_id": (organization || business)&.id,
        "gh.copilot_insights.days": days
      )

      if cus
        ::CopilotInsightsUsage::CusDashboardService.call(**kwargs)
      elsif spark
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
      when MetricsKey::ImpactMetrics
        result.impact_metrics
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
      when MetricsKey::ImpactMetrics then "impact"
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
