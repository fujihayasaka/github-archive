# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    module Dashboards
      class PullRequestLeadTime < Copilot::Metrics::Dashboards::Base

        sig { override.returns(Copilot::Types::AverageContributionPayload) }
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
            name: "Average pull request lead time",
            description: "Tracks the median time from pull request creation to merge on ‘main’ as an indicator of workflow efficiency, integration speed, and overall developer experience.",
            category: "Velocity",
            path: Rails.application.routes.url_helpers.pull_request_lead_time_org_insights_path(owner),
          }
        end

        sig { override.returns(T::Boolean) }
        def should_render?
          owner.feature_flag_enabled?(:copilot_metrics_insights_navigator, default: false) ||
          !!owner.business&.feature_flag_enabled?(:copilot_metrics_insights_navigator, default: false)
        end

        private

        sig { override.returns(T::Array[Copilot::Types::AverageContributionDateBucket]) }
        memoize def data
          summaries = Copilot::MetricSummary
                      .where(owner: owner)
                      .where(start_date: OLDEST_ACTIVITY_INSIGHTS_DAYS.days.ago..)
                      .where("pr_lead_times is not null")
                      .order(start_date: :asc)

          active_summaries = summaries.filter do |summary|
            data = summary.pr_lead_times
            summary.valid? && data.present? &&
              (data.dig("no_copilot", "average") > 0 ||
              data.dig("low_engagement", "average") > 0 ||
              data.dig("moderate_engagement", "average") > 0 ||
              data.dig("high_engagement", "average") > 0)
          end

          active_summaries.map do |summary|
            data = summary.pr_lead_times
            {
              id: summary.id.to_s,
              label: "Week #{summary.start_date.cweek}",
              shortLabel: "W#{summary.start_date.cweek}",
              startDate: summary.start_date,
              endDate: summary.end_date,
              noCopilot: {
                average: data.dig("no_copilot", "average"),
                percentDifference: data.dig("no_copilot", "percent_difference")
              },
              lowEngagement: {
                average: data.dig("low_engagement", "average"),
                percentDifference: data.dig("low_engagement", "percent_difference")
              },
              moderateEngagement: {
                average: data.dig("moderate_engagement", "average"),
                percentDifference: data.dig("moderate_engagement", "percent_difference")
              },
              highEngagement: {
                average: data.dig("high_engagement", "average"),
                percentDifference: data.dig("high_engagement", "percent_difference")
              }
            }
          end.compact
        end

        sig { override.returns(T::Array[Symbol]) }
        memoize def csv_headers
          %i[label startDate endDate noCopilotAverage lowEngagementAverage lowEngagementPercentDifference moderateEngagementAverage moderateEngagementPercentDifference highEngagementAverage highEngagementPercentDifference]
        end
      end
    end
  end
end
