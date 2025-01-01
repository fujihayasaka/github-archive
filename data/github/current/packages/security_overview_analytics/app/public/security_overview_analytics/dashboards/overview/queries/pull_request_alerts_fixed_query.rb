# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class PullRequestAlertsFixedQuery < PreventionAbstractQuery
          extend T::Helpers
          include AlertsFixedQueryBase

          class Result < T::Struct
            const :count, Integer, default: 0
            const :total, Integer, default: 0
            const :percentage, Float, default: 0.0
          end

          sig { returns(Result) }
          def perform
            # Return empty if the query is not valid.
            # Query is considered invalid if non-codeql filters are applied.
            return Result.new unless @alerts_filterer.has_valid_filters?

            result = query(
              repos_filterer: @repos_filterer,
              alerts_filterer: @alerts_filterer,
              start_date: @start_date,
              end_date: @end_date
            )

            Result.new(
              count: result[:fixed]&.to_i || 0,
              total: result[:total]&.to_i || 0,
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
