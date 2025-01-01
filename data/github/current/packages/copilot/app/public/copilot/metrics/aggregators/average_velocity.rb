# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    module Aggregators
      class AverageVelocity < Copilot::Metrics::Aggregators::Base
        MINIMUM_DATA_POINTS = 5
        BucketedAverage = T.type_alias do
          {
            no_copilot: T::Hash[Symbol, Numeric],
            low_engagement: T::Hash[Symbol, Numeric],
            moderate_engagement: T::Hash[Symbol, Numeric],
            high_engagement: T::Hash[Symbol, Numeric],
          }
        end

        sig { returns(T.nilable(BucketedAverage)) }
        def prs_merged
          average_velocity(:prs_merged)
        end

        sig { returns(T.nilable(BucketedAverage)) }
        def commit_counts
          average_velocity(:commit_count)
        end

        sig { returns(T.nilable(BucketedAverage)) }
        def pr_lead_time
          average_velocity(:pr_lead_time)
        end

        private

        sig { params(type: Symbol).returns(T.nilable(BucketedAverage)) }
        def average_velocity(type)
          return unless entity_memberships.length >= MINIMUM_DATA_POINTS
          result = [:no_copilot, :low_engagement, :moderate_engagement, :high_engagement].each_with_object({}) do |engagement_segment, memo|
            total_events = bucketed_insights_activities[engagement_segment].sum { |insight| insight[type] }
            total_members = bucketed_insights_activities[engagement_segment].size
            num_sig = type == :prs_merged ? 1 : 0
            average = total_members > 0 ? (total_events.to_f / total_members).round(num_sig) : 0.0
            if engagement_segment == :no_copilot
              percent_difference = nil
            else
              no_copilot_average = memo[:no_copilot][:average]
              percent_difference = no_copilot_average > 0 ? ((average - no_copilot_average).to_f / no_copilot_average).round(2) : nil
            end

            memo[engagement_segment] = {
              average: average,
              percent_difference: percent_difference
            }
          end

          T.cast(result, BucketedAverage)
        end

        sig do
          returns({
            no_copilot: T::Array[T::Hash[Symbol, Integer]],
            low_engagement: T::Array[T::Hash[Symbol, Integer]],
            moderate_engagement: T::Array[T::Hash[Symbol, Integer]],
            high_engagement: T::Array[T::Hash[Symbol, Integer]],
          })
        end
        def bucketed_insights_activities
          separate_engagements = sorted_insights_activities.group_by do |activity|
            if activity[:engagement_events] == 0
              :no_copilot
            else
              :engagement
            end
          end

          engaged_activities = separate_engagements[:engagement] || []
          engaged_size = engaged_activities.size
          first_third = engaged_size / 3
          second_third = first_third * 2

          {
            no_copilot: separate_engagements[:no_copilot] || [],
            low_engagement: T.must(engaged_activities[0...first_third]),
            moderate_engagement: T.must(engaged_activities[first_third...second_third]),
            high_engagement: T.must(engaged_activities[second_third..]),
          }
        end

        sig { returns(T::Array[T::Hash[Symbol, Integer]]) }
        memoize def sorted_insights_activities
          summed_insights_activities = entity_memberships.map do |entity_membership|
            entity_membership.velocity_activity_for_period(
              start_date: @start_date,
              end_date: @end_date,
            )
          end

          summed_insights_activities.sort_by { |activity| activity[:engagement_events] }
        end

        sig { returns(T::Array[Copilot::EntityMembership]) }
        memoize def entity_memberships
          Copilot::EntityMembership.for_organization(@owner).includes(:platform_activity, :copilot_activity).to_a
        end
      end
    end
  end
end
