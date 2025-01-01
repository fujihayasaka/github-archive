# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    module Dashboards
      class UserOnboarding < Copilot::Metrics::Dashboards::Base
        # We were only able to backfill auth data as far back as 1/6/2025. Since that will be fewer than 100 days from
        # The initial release, we need to cut off the historical data at that date. This can be removed after 4/14/2025.
        EARLIEST_BACKFILL_DATE = Date.new(2025, 1, 6)

        sig { override.returns(Copilot::Types::AdoptionMetricsPayload) }
        def payload
          {
            overallStartDate: data.first&.dig(:startDate) || Date.current,
            overallEndDate: data.last&.dig(:endDate) || Date.current,
            data:,
          }
        end

        sig { override.returns(Copilot::Types::MetricsCatalogEntry) }
        def catalog_entry
          {
            name: "Copilot user onboarding",
            description: "Tracks engagement to evaluate onboarding effectiveness and pinpoint areas for improvement.",
            category: "Copilot",
            path: Rails.application.routes.url_helpers.copilot_user_onboarding_org_insights_path(owner),
          }
        end

        private

        sig { override.returns(T::Array[Copilot::Types::AdoptionMetricsBucket]) }
        memoize def data
          return [] unless onboarding_data.any?

          weeks_with_full_data = onboarding_data.select { |bucket| bucket[:startDate] >= EARLIEST_BACKFILL_DATE }

          first_week_with_seats_index = weeks_with_full_data.index { |bucket| bucket[:total] > 0 } || weeks_with_full_data.size
          weeks_with_full_data[first_week_with_seats_index..] || []
        end

        sig { override.returns(T::Array[Symbol]) }
        memoize def csv_headers
          %i[label startDate endDate total dormant inactive active]
        end

        sig { returns(T::Array[Copilot::Types::AdoptionMetricsBucket]) }
        memoize def onboarding_data
          summaries = Copilot::MetricSummary
                        .where(owner: owner)
                        .where(start_date: Copilot::Metrics::SummaryJob::SUMMARY_RETENTION_DAYS.days.ago..)
                        .order(start_date: :asc)
          summaries.map do |summary|
            {
              id: summary.id.to_s,
              label: "Week #{summary.start_date.cweek}",
              shortLabel: "W#{summary.start_date.cweek}",
              startDate: summary.start_date,
              endDate: summary.end_date,
              total: summary.total_seats,
              active: summary.active_seats,
              inactive: summary.inactive_seats,
              dormant: summary.dormant_seats
            }
          end
        end
      end
    end
  end
end
