# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    module Dashboards
      class CompletionsAcceptanceRate < Copilot::Metrics::Dashboards::Base
        sig { override.returns(Copilot::Types::CodeAcceptanceRatePayload) }
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
            name: "Copilot code completions acceptance rate",
            description: "Tracks the percentage of Copilot’s code completions suggestions that developers accept and use.",
            category: "Copilot",
            path: Rails.application.routes.url_helpers.copilot_code_completions_acceptance_rate_org_insights_path(owner),
          }
        end

        sig { override.returns(T::Boolean) }
        def should_render?
          owner.feature_flag_enabled?(:copilot_metrics_insights_navigator, default: false) ||
          !!owner.business&.feature_flag_enabled?(:copilot_metrics_insights_navigator, default: false)
        end

        private

        sig { override.returns(T::Array[Copilot::Types::CodeAcceptanceRateDateBucket]) }
        memoize def data
          return [] unless summary_data.any?

          first_period_with_data_index = summary_data.index do |bucket|
            bucket[:lowEngagement][:total] > 0 || bucket[:moderateEngagement][:total] > 0 || bucket[:highEngagement][:total] > 0
          end || summary_data.size
          summary_data[first_period_with_data_index..] || []
        end

        sig { returns(T::Array[Copilot::Types::CodeAcceptanceRateDateBucket]) }
        memoize def summary_data
          summaries = Copilot::MetricSummary
                      .where(owner: owner)
                      .where(start_date: OLDEST_ACTIVITY_INSIGHTS_DAYS.days.ago..)
                      .where("code_suggestion_events is not null")
                      .order(start_date: :asc)

          summaries.map do |summary|
            # ensure that all of the data we're expecting is present
            next unless summary.code_suggestion_events.present? && summary.valid?

            events = summary.code_suggestion_events
            {
              id: summary.id.to_s,
              label: "Week #{summary.start_date.cweek}",
              shortLabel: "W#{summary.start_date.cweek}",
              startDate: summary.start_date,
              endDate: summary.end_date,
              lowEngagement: {
                total: events.dig("low_engagement", "total"),
                accepted: events.dig("low_engagement", "accepted"),
                acceptanceRate: events.dig("low_engagement", "acceptance_rate")
              },
              moderateEngagement: {
                total: events.dig("moderate_engagement", "total"),
                accepted: events.dig("moderate_engagement", "accepted"),
                acceptanceRate: events.dig("moderate_engagement", "acceptance_rate")
              },
              highEngagement: {
                total: events.dig("high_engagement", "total"),
                accepted: events.dig("high_engagement", "accepted"),
                acceptanceRate: events.dig("high_engagement", "acceptance_rate")
              }
            }
          end.compact
        end

        sig { override.returns(T::Array[Symbol]) }
        memoize def csv_headers
          %i[label startDate endDate lowEngagementTotal lowEngagementAccepted lowEngagementAcceptanceRate
             moderateEngagementTotal moderateEngagementAccepted moderateEngagementAcceptanceRate
             highEngagementTotal highEngagementAccepted highEngagementAcceptanceRate]
        end
      end
    end
  end
end
