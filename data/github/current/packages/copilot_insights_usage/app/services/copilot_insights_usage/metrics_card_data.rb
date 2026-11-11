# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class MetricsCardData
    include GitHub::Memoizer
    include ActionView::Helpers::NumberHelper

    LOOKBACK_DAYS = 28

    sig { params(usage_data: T::Array[T::Hash[String, T.untyped]]).void }
    def initialize(usage_data:)
      @usage_data = T.let(usage_data.last(LOOKBACK_DAYS), T::Array[T::Hash[String, T.untyped]])
    end

    sig { returns(CopilotInsightsUsage::Types::MetricsCardPayload) }
    def payload
      { data: data }
    end

    private

    sig { returns(CopilotInsightsUsage::Types::MetricsCardData) }
    memoize def data
      current_day_record = @usage_data.last

      monthly_active_users = current_day_record&.dig("monthly_active_users") || 0
      monthly_active_agent_users = current_day_record&.dig("monthly_active_agent_users") || 0
      most_used_model = find_most_used_model(@usage_data)

      agent_adoption_rate = monthly_active_users > 0 ? (monthly_active_agent_users.to_f / monthly_active_users * 100).round : 0

      {
        activeUsersCardData: {
          totalActiveUsers: number_with_delimiter(monthly_active_users),
        },
        agentAdoptionCardData: {
          usersTriedAgent: number_with_delimiter(monthly_active_agent_users),
          totalUsers: number_with_delimiter(monthly_active_users),
          rate: agent_adoption_rate
        },
        modelCardData: {
          modelName: most_used_model
        }
      }
    end

    sig { params(daily_data: T::Array[T::Hash[String, T.untyped]]).returns(String) }
    def find_most_used_model(daily_data)
      model_totals = Hash.new(0)

      daily_data.each do |daily_record|
        totals_by_model = daily_record.dig("totals_by_model_feature") || []
        totals_by_model.each do |model_data|
          model_name = model_data.dig("model")
          request_count = model_data.dig("user_initiated_interaction_count") || 0
          model_totals[model_name] += request_count if model_name
        end
      end

      filtered_models = model_totals.reject { |model, _count| model&.downcase == "unknown" }
      most_used_model = filtered_models.max_by { |_model, count| count }&.first || "Unknown Model"
      Utilities.display_label_for_model(most_used_model)
    end
  end
end
