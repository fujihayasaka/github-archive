# typed: strict
# frozen_string_literal: true

module CopilotInsightsUsage
  class Types
    LineChartDataPoint = T.type_alias do
      {
        id: String,
        label: String,
        startDate: Date,
        endDate: Date,
        value: T.any(Float, Integer),
      }
    end

    LineChartPayload = T.type_alias do
      {
        startDate: T.nilable(Date),
        endDate: T.nilable(Date),
        data: T::Array[LineChartDataPoint],
      }
    end

    ColumnChartDataPoint = T.type_alias do
      {
        id: String,
        label: String,
        startDate: Date,
        endDate: Date,
        values: T::Hash[String, T.any(Float, Integer)],
      }
    end

    ColumnChartPayload = T.type_alias do
      {
        startDate: T.nilable(Date),
        endDate: T.nilable(Date),
        data: T::Array[ColumnChartDataPoint],
      }
    end

    CategoryColumnChartDataPoint = T.type_alias do
      {
        id: String,
        label: String,
        values: T::Hash[String, T.any(Float, Integer)],
      }
    end

    CategoryColumnChartPayload = T.type_alias do
      {
        data: T::Array[CategoryColumnChartDataPoint],
      }
    end

    ModelUsagePerLanguageDataPoint = T.type_alias do
      {
        id: String,
        label: String,
        values: T::Hash[String, T.any(Float, Integer)],
      }
    end

    ModelUsagePerLanguagePayload = T.type_alias do
      {
        data: T::Array[ModelUsagePerLanguageDataPoint],
      }
    end

    StackedAreaChartDataPoint = T.type_alias do
      {
        id: String,
        label: String,
        startDate: Date,
        endDate: Date,
        values: T::Array[{
          name: String,
          percentage: T.any(Float, Integer),
        }],
      }
    end

    StackedAreaChartPayload = T.type_alias do
      {
        startDate: T.nilable(Date),
        endDate: T.nilable(Date),
        data: T::Array[StackedAreaChartDataPoint],
      }
    end

    DonutChartDataPoint = T.type_alias do
      {
        name: String,
        y: T.any(Float, Integer),
      }
    end

    DonutChartPayload = T.type_alias do
      {
        data: T::Array[DonutChartDataPoint],
      }
    end

    MultipleSeriesLineChartDataPoint = T.type_alias do
      {
        id: String,
        label: String,
        startDate: Date,
        endDate: Date,
        values: T::Array[{
          name: String,
          value: T.any(Float, Integer),
        }],
      }
    end

    MultipleSeriesLineChartPayload = T.type_alias do
      {
        startDate: T.nilable(Date),
        endDate: T.nilable(Date),
        data: T::Array[MultipleSeriesLineChartDataPoint],
      }
    end

    MetricsCardPayload = T.type_alias do
      {
        data: MetricsCardData,
      }
    end

    MetricsCardData = T.type_alias do
      {
        activeUsersCardData: {
          totalActiveUsers: String,
        },
        agentAdoptionCardData: {
          usersTriedAgent: String,
          totalUsers: String,
          rate: T.any(Float, Integer)
        },
        modelCardData: {
          modelName: String
        }
      }
    end
  end
end
