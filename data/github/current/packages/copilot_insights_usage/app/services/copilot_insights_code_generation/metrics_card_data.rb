# typed: strict
# frozen_string_literal: true

module CopilotInsightsCodeGeneration
  class MetricsCardData
    include GitHub::Memoizer
    include ActionView::Helpers::NumberHelper
    include UsersHelper

    LOOKBACK_DAYS = 28

    sig { params(usage_data: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_data:)
      @usage_data = T.let(usage_data.last(LOOKBACK_DAYS), T::Array[T::Hash[String, T.untyped]])
    end

    sig { returns(CopilotInsights::Types::MetricsCardPayload) }
    def payload
      { data: data }
    end

    private

    sig { returns(CopilotInsights::Types::MetricsCardData) }
    memoize def data
      {
        linesChangedByAllModesCardData: social_count(total_lines_changed_with_ai),
        agentContributionCardData: "#{agent_contribution_rate}%",
        averageLinesDeletedByAgentCardData: social_count(average_lines_deleted_by_agent)
      }
    end

    sig { returns(Integer) }
    def total_lines_changed_with_ai
      @usage_data.sum do |day|
        (day["totals_by_feature"] || []).sum do |feature|
          feature["loc_added_sum"].to_i + feature["loc_deleted_sum"].to_i
        end
      end
    end

    sig { returns(Float) }
    def agent_contribution_rate
      agent_total = @usage_data.sum do |day|
        (day["totals_by_feature"] || []).select { |f| CopilotInsightsUsage::Utilities.valid_initiated_feature?(feature: f["feature"], initiated_by: "agent") }.sum do |feature|
          feature["loc_added_sum"].to_i + feature["loc_deleted_sum"].to_i
        end
      end

      all_total = total_lines_changed_with_ai
      CopilotInsightsUsage::Utilities.calculate_percentage(agent_total, all_total).to_f
    end

    sig { returns(Integer) }
    def average_lines_deleted_by_agent
      current_day_record = @usage_data.last

      agent_user_count = current_day_record&.dig("monthly_active_agent_users").to_i
      return 0 unless agent_user_count > 0

      report_month = begin
        Date.parse(current_day_record&.dig("day").to_s).month
      rescue ArgumentError # handle potential date parsing errors, mostly for tests
        nil
      end

      ff_enabled = FeatureFlag.vexi.enabled?(:copilot_insights_avg_deleted_loc_fix, default: false)

      total_deleted = @usage_data.sum do |day|
        if ff_enabled
          # If we don't have a valid report month, skip all sum iterations and just return 0
          return 0 if report_month.nil?

          month = begin
            Date.parse(day["day"].to_s).month
          rescue ArgumentError # handle potential date parsing errors, mostly for tests
            nil
          end

          next 0 if month.nil? || month != report_month
        end

        (day["totals_by_feature"] || [])
          .select { |f| CopilotInsightsUsage::Utilities.valid_initiated_feature?(feature: f["feature"], initiated_by: "agent") }
          .sum { |feature| feature["loc_deleted_sum"].to_i }
      end

      (total_deleted.to_f / agent_user_count).round
    end
  end
end
