# typed: true
# frozen_string_literal: true

module CopilotInsightsUsage
  class DashboardService
    Result = Struct.new(:code_generation_metrics, :usage_metrics, :display_flags, :latest_date, keyword_init: true)

    DEFAULT_REPORT_CLASS = ::Copilot::Metrics::UsageReport

    def self.call(business: nil, organization: nil, days:, report_class: DEFAULT_REPORT_CLASS)
      new(business: business, organization: organization, days: days, report_class: report_class).call
    end

    def initialize(business: nil, organization: nil, days:, report_class: DEFAULT_REPORT_CLASS)
      if business.nil? && organization.nil?
        raise ArgumentError, "Either business or organization must be provided"
      end
      if business && organization
        raise ArgumentError, "Cannot provide both business and organization"
      end

      @business = business
      @organization = organization
      @days = days
      @report_class = report_class
    end

    def call
      usage_report = if @organization
        if FeatureFlag.vexi.enabled?("copilot_insights_org_query_enterprise_filter", @organization, default: false)
          @report_class.new(organization_id: @organization.id, enterprise_id: @organization.business&.id)
        else
          @report_class.new(organization_id: @organization.id)
        end
      else
        @report_class.new(enterprise_id: @business.id)
      end

      all_days_data = []
      fetched_data = []
      display_error = false
      display_blankslate = false
      latest_date = nil

      begin
        all_days_data = usage_report.fetch
        fetched_data = all_days_data.last(@days)
        latest_date = if derive_latest_date_from_fetch?
          all_days_data.last&.dig("day")&.to_date
        else
          usage_report.get_latest_date
        end
      rescue ::Copilot::Metrics::UsageReport::NoDataAvailableError
        display_blankslate = true
      rescue ::Copilot::Metrics::UsageReport::Error => e
        ::Failbot.report(e)
        display_error = true
      end

      usage_metrics = build_usage_metrics(fetched_data, all_days_data)

      code_generation_metrics = build_code_generation_metrics(fetched_data, all_days_data)

      code_generation_disclaimer = display_code_generation_disclaimer
      usage_disclaimer = display_usage_disclaimer
      no_matching_results = false

      # Check if the timeframe slice has no meaningful activity.
      # This must run before the blankslate check to avoid masking it.
      # The frontend decides whether to show a blankslate (e.g. copilot disabled)
      # or a "no matching results" card based on policy state.
      if display_no_matching_results?(display_blankslate, display_error, fetched_data)
        no_matching_results = true
      end

      # if the metrics are empty or daily active users is empty, set display_flags to show blankslate
      # but not when the timeframe simply has no matching results
      if !no_matching_results && ((usage_metrics.empty? && code_generation_metrics.empty?) || daily_active_users_empty?(usage_metrics))
        display_blankslate = true
        code_generation_disclaimer = false
        usage_disclaimer = false
        display_error = false
      end

      Result.new(
        code_generation_metrics: code_generation_metrics,
        usage_metrics: usage_metrics,
        display_flags: {
          blankslate: display_blankslate,
          code_generation_disclaimer: code_generation_disclaimer,
          usage_disclaimer: usage_disclaimer,
          error: display_error,
          no_matching_results: no_matching_results,
        },
        latest_date: latest_date,
      )
    end

    private

    def daily_active_users_empty?(usage_metrics)
      daily_active_users_data = usage_metrics.dig(:dailyActiveUsers, :data)
      return true if daily_active_users_data.nil? || daily_active_users_data.empty?
      daily_active_users_data.all? { |data_point| data_point[:value].to_i <= 0 }
    end

    def all_metrics_empty?(data)
      return true if data.nil? || data.empty?

      data.none? { |day| day_has_activity?(day) }
    end

    def day_has_activity?(day)
      return false unless day.is_a?(Hash)
      day.fetch("daily_active_users", 0).to_i > 0
    end

    def display_code_generation_disclaimer
      entity = @organization || @business
      FeatureFlag.vexi.enabled?("copilot_insights_code_generation_disclaimer", entity, default: false)
    end

    def display_usage_disclaimer
      entity = @organization || @business
      FeatureFlag.vexi.enabled?("copilot_insights_usage_disclaimer", entity, default: false)
    end

    def display_no_matching_results?(display_blankslate, display_error, fetched_data)
      !display_blankslate && !display_error && all_metrics_empty?(fetched_data)
    end

    def derive_latest_date_from_fetch?
      entity = @organization || @business
      FeatureFlag.vexi.enabled?("copilot_insights_derive_latest_date_from_fetch", entity, default: false)
    end

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
        metricCardsData: CopilotInsightsCodeGeneration::MetricsCardData.new(usage_data: all_days_data).payload,
        dailyTotalLinesOfCode: CopilotInsightsCodeGeneration::DailyTotalLinesOfCodeData.new(usage_report: fetched_data).payload,
        userInitiatedCodeChanges: CopilotInsightsCodeGeneration::UserInitiatedCodeChangesData.new(usage_report: fetched_data).payload,
        agentInitiatedCodeChanges: CopilotInsightsCodeGeneration::AgentInitiatedCodeChangesData.new(usage_report: fetched_data).payload,
        userInitiatedCodeChangesPerLanguage: CopilotInsightsCodeGeneration::UserInitiatedCodeChangesPerLanguageData.new(usage_report: fetched_data).payload,
        agentInitiatedCodeChangesPerLanguage: CopilotInsightsCodeGeneration::AgentInitiatedCodeChangesPerLanguageData.new(usage_report: fetched_data).payload,
        userInitiatedCodeChangesPerModel: CopilotInsightsCodeGeneration::UserInitiatedCodeChangesPerModelData.new(usage_report: fetched_data).payload,
        agentInitiatedCodeChangesPerModel: CopilotInsightsCodeGeneration::AgentInitiatedCodeChangesPerModelData.new(usage_report: fetched_data).payload,
      }
    end
  end
end
