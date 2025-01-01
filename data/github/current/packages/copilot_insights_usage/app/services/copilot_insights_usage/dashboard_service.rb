# typed: true
# frozen_string_literal: true

module CopilotInsightsUsage
  class DashboardService
    Result = Struct.new(:code_generation_metrics, :usage_metrics, :display_blankslate, :display_error, :latest_date, keyword_init: true)

    def self.call(business:, days:)
      new(business: business, days: days).call
    end

    def initialize(business:, days:)
      @business = business
      @days = days
    end

    def call
      usage_report = ::Copilot::Metrics::UsageReport.new(enterprise_id: @business&.id)

      all_days_data = []
      fetched_data = []
      display_error = false
      display_blankslate = false
      latest_date = nil

      begin
        all_days_data = usage_report.fetch
        fetched_data = all_days_data.last(@days)
        latest_date = usage_report.get_latest_date
      rescue ::Copilot::Metrics::UsageReport::NoDataAvailableError
        display_blankslate = true
      rescue ::Copilot::Metrics::UsageReport::Error => e
        ::Failbot.report(e)
        display_error = true
      end

      usage_metrics = build_usage_metrics(fetched_data, all_days_data)

      code_generation_metrics = build_code_generation_metrics(fetched_data, all_days_data)

      Result.new(
        code_generation_metrics: code_generation_metrics,
        usage_metrics: usage_metrics,
        display_blankslate: display_blankslate,
        display_error: display_error,
        latest_date: latest_date,
      )
    end

    private

    def build_usage_metrics(fetched_data, all_days_data)
      {
        dailyActiveUsers: CopilotInsightsUsage::DailyActiveUsersData.new(usage_report: fetched_data).payload,
        weeklyActiveUsers: CopilotInsightsUsage::WeeklyActiveUsersData.new(usage_report: fetched_data).payload,
        averageRequestsPerActiveChatUser: CopilotInsightsUsage::AverageRequestsPerActiveChatUser.new(usage_report: fetched_data).payload,
        requestsPerFeature: CopilotInsightsUsage::RequestsPerFeatureData.new(usage_report: fetched_data).payload,
        codeCompletions: CopilotInsightsUsage::CodeCompletionsData.new(usage_report: fetched_data).payload,
        codeCompletionsAcceptanceRate: CopilotInsightsUsage::CodeCompletionsAcceptanceRateData.new(usage_report: fetched_data).payload,
        modelUsagePerDay: CopilotInsightsUsage::ModelUsagePerDayData.new(usage_report: fetched_data).payload,
        metricCardsData: CopilotInsightsUsage::MetricsCardData.new(usage_data: all_days_data).payload,
        modelUsage: CopilotInsightsUsage::ModelUsageData.new(usage_report: fetched_data).payload,
        modelUsagePerFeature: CopilotInsightsUsage::ModelUsagePerFeature.new(usage_report: fetched_data).payload,
        languageUsagePerDay: CopilotInsightsUsage::LanguageUsagePerDayData.new(usage_report: fetched_data).payload,
        languageUsage: CopilotInsightsUsage::LanguageUsageData.new(usage_report: fetched_data).payload,
        modelUsagePerLanguage: CopilotInsightsUsage::ModelUsagePerLanguage.new(usage_report: fetched_data).payload,
      }
    end

    def build_code_generation_metrics(fetched_data, all_days_data)
      {
        linesOfCodeAcceptanceRate: CopilotInsightsCodeGeneration::LinesOfCodeAcceptanceRateData.new(usage_report: fetched_data).payload,
        linesOfCodePerDay: CopilotInsightsCodeGeneration::LinesOfCodePerDayData.new(usage_report: fetched_data).payload,
        linesOfCodePerLanguage: CopilotInsightsCodeGeneration::LinesOfCodePerLanguageData.new(usage_report: fetched_data).payload,
        linesOfCodePerMode: CopilotInsightsCodeGeneration::LinesOfCodePerModeData.new(usage_report: fetched_data).payload,
        linesOfCodePerModel: CopilotInsightsCodeGeneration::LinesOfCodePerModelData.new(usage_report: fetched_data).payload,
        metricCardsData: CopilotInsightsCodeGeneration::MetricsCardData.new.payload,
      }
    end
  end
end
