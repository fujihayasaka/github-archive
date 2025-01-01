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
          owner.feature_enabled?(:copilot_metrics_insights_navigator) ||
          !!owner.business&.feature_enabled?(:copilot_metrics_insights_navigator)
        end

        private

        sig { override.returns(T::Array[Copilot::Types::AverageContributionDateBucket]) }
        memoize def data
          if GitHub.flipper[:copilot_metric_summaries_m2_query_live_data].enabled?
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
          else
            mock_data
          end
        end

        sig { override.returns(T::Array[Symbol]) }
        memoize def csv_headers
          %i[label startDate endDate noCopilotAverage lowEngagementAverage lowEngagementPercentDifference moderateEngagementAverage moderateEngagementPercentDifference highEngagementAverage highEngagementPercentDifference]
        end

        sig { returns(T::Array[Copilot::Types::AverageContributionDateBucket]) }
        def mock_data
          10.downto(1).map do |i|
            date = Date.current.beginning_of_week(:monday) - 7 * i

            no_copilot_average = rand(50..100).to_i
            low_engagement_average = rand(50..100).to_i
            low_engagement_percent_difference = ((low_engagement_average - no_copilot_average) / no_copilot_average.to_f)
            moderate_engagement_average = rand(0..50).to_i
            moderate_engagement_percent_difference = ((moderate_engagement_average - no_copilot_average) / no_copilot_average.to_f)
            high_engagement_average = rand(0..20).to_i
            high_engagement_percent_difference = ((high_engagement_average - no_copilot_average) / no_copilot_average.to_f)

            {
              id: i.to_s,
              label: "Week #{11 - i}",
              shortLabel: "W#{11 - i}",
              startDate: date,
              endDate: date + 6.days,
              noCopilot: {
                average: no_copilot_average,
                percentDifference: nil
              },
              lowEngagement: {
                average: low_engagement_average,
                percentDifference: low_engagement_percent_difference
              },
              moderateEngagement: {
                average: moderate_engagement_average,
                percentDifference: moderate_engagement_percent_difference
              },
              highEngagement: {
                average: high_engagement_average,
                percentDifference: high_engagement_percent_difference
              }
            }
          end
        end
      end
    end
  end
end
