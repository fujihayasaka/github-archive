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
          owner.feature_enabled?(:copilot_metrics_insights_navigator) ||
          !!owner.business&.feature_enabled?(:copilot_metrics_insights_navigator)
        end

        private

        sig { override.returns(T::Array[Copilot::Types::CodeAcceptanceRateDateBucket]) }
        memoize def data
          if GitHub.flipper[:copilot_metric_summaries_m1_query_live_data].enabled?
            return [] unless summary_data.any?

            first_period_with_data_index = summary_data.index do |bucket|
              bucket[:lowEngagement][:total] > 0 || bucket[:moderateEngagement][:total] > 0 || bucket[:highEngagement][:total] > 0
            end || summary_data.size
            summary_data[first_period_with_data_index..] || []
          else
            mock_data
          end
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

        sig { returns(T::Array[Copilot::Types::CodeAcceptanceRateDateBucket]) }
        def mock_data
          10.downto(1).map do |i|
            date = Date.current.beginning_of_week(:monday) - 7 * i

            low_engagement_total = rand(100..10000)
            low_engagement_accepted = rand((low_engagement_total * 0.3).to_i..(low_engagement_total * 0.7).to_i)
            low_engagement_acceptance_rate = (low_engagement_accepted.to_f / low_engagement_total).round(4)
            moderate_engagement_total = rand(100..10000)
            moderate_engagement_accepted = rand((moderate_engagement_total * 0.5).to_i..(moderate_engagement_total * 0.8).to_i)
            moderate_engagement_acceptance_rate = (moderate_engagement_accepted.to_f / moderate_engagement_total).round(4)
            high_engagement_total = rand(100..10000)
            high_engagement_accepted = rand((high_engagement_total * 0.7).to_i..(high_engagement_total * 0.9).to_i)
            high_engagement_acceptance_rate = (high_engagement_accepted.to_f / high_engagement_total).round(4)

            {
              id: i.to_s,
              label: "Week #{11 - i}",
              shortLabel: "W#{11 - i}",
              startDate: date,
              endDate: date + 6.days,
              lowEngagement: {
                total: low_engagement_total,
                accepted: low_engagement_accepted,
                acceptanceRate: low_engagement_acceptance_rate.to_f
              },
              moderateEngagement: {
                total: moderate_engagement_total,
                accepted: moderate_engagement_accepted,
                acceptanceRate: moderate_engagement_acceptance_rate.to_f
              },
              highEngagement: {
                total: high_engagement_total,
                accepted: high_engagement_accepted,
                acceptanceRate: high_engagement_acceptance_rate.to_f
             }
            }
          end
        end
      end
    end
  end
end
