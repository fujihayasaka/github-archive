# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module CodeScanningMetrics
      module Queries
        class AlertsFixedWithAutofixQuery < AbstractQuery
          extend T::Helpers
          include AlertsFixedWithAutofixQueryBase

          sig { returns(Result) }
          def perform
            query(
              repos_filterer: @repos_filterer,
              alerts_filterer: @alerts_filterer,
              start_date: @start_date,
              end_date: @end_date
            )
          end
        end
      end
    end
  end
end
