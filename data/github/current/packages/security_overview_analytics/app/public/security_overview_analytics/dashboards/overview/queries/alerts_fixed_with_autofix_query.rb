# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AlertsFixedWithAutofixQuery < PreventionAbstractQuery
          extend T::Helpers
          include AlertsFixedWithAutofixQueryBase

          sig { returns(Result) }
          def perform
            # Return empty if the query is not valid.
            # Query is considered invalid if non-codeql filters are applied.
            return Result.new unless @alerts_filterer.has_valid_filters?

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
