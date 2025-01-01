# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class AlertsFixedQuery < AbstractQuery
          extend T::Helpers
          include AlertsFixedQueryBase

          class Result < T::Struct
            const :count, Integer
            const :total, Integer
            const :percentage, Float
          end

          sig { returns(Result) }
          def perform
            result = query(
              repos_filterer: @repos_filterer,
              alerts_filterer: @alerts_filterer,
              start_date: @start_date,
              end_date: @end_date
            )

            Result.new(
              count: result[:fixed]&.to_i || 0,
              total: result[:total],
              percentage: percentage(
                result[:fixed]&.to_i || 0,
                result[:total]&.to_i || 0
              ),
            )
          end
        end
      end
    end
  end
end
