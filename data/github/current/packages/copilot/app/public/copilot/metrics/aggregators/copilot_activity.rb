# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    module Aggregators
      class CopilotActivity < Copilot::Metrics::Aggregators::Base
        MINIMUM_DATA_POINTS = 5
        BucketedAcceptanceRate = T.type_alias do
          {
            low_engagement: T::Hash[Symbol, Numeric],
            moderate_engagement: T::Hash[Symbol, Numeric],
            high_engagement: T::Hash[Symbol, Numeric],
          }
        end

        sig { returns(T.nilable(BucketedAcceptanceRate)) }
        def code_suggestion_events
          return unless entity_memberships.length >= MINIMUM_DATA_POINTS

          result = [:low_engagement, :moderate_engagement, :high_engagement].each_with_object({}) do |engagement_segment, memo|
            total = bucketed_insights_activities[engagement_segment].sum { |insight| insight[:code_suggestion_events] }
            accepted = bucketed_insights_activities[engagement_segment].sum { |insight| insight[:code_suggestion_events_accepted] }
            rate = total > 0 ? (accepted.to_f / total).round(4) : 0.0

            memo[engagement_segment] = {
              total: total,
              accepted: accepted,
              acceptance_rate: rate,
            }
          end

          T.cast(result, BucketedAcceptanceRate)
        end

        sig { returns(T.nilable(BucketedAcceptanceRate)) }
        def loc_generated
          return unless entity_memberships.length >= MINIMUM_DATA_POINTS

          result = [:low_engagement, :moderate_engagement, :high_engagement].each_with_object({}) do |engagement_segment, memo|
            total = bucketed_insights_activities[engagement_segment].sum { |insight| insight[:loc_suggested] }
            accepted = bucketed_insights_activities[engagement_segment].sum { |insight| insight[:loc_accepted] }
            rate = total > 0 ? (accepted.to_f / total).round(4) : 0.0

            memo[engagement_segment] = {
              total: total,
              accepted: accepted,
              acceptance_rate: rate,
            }
          end

          T.cast(result, BucketedAcceptanceRate)
        end

        private

        sig do
          returns({
            low_engagement: T::Array[T::Hash[Symbol, Integer]],
            moderate_engagement: T::Array[T::Hash[Symbol, Integer]],
            high_engagement: T::Array[T::Hash[Symbol, Integer]],
          })
        end
        memoize def bucketed_insights_activities
          total_size = sorted_insights_activities.size
          first_third = total_size / 3
          second_third = 2 * first_third

          {
            low_engagement: T.must(sorted_insights_activities[0...first_third]),
            moderate_engagement: T.must(sorted_insights_activities[first_third...second_third]),
            high_engagement: T.must(sorted_insights_activities[second_third..]),
          }
        end

        sig { returns(T::Array[T::Hash[Symbol, Integer]]) }
        memoize def sorted_insights_activities
          summed_insights_activities = entity_memberships.map do |entity_membership|
            entity_membership.copilot_activity_for_period(start_date: start_date, end_date: end_date)
          end

          filtered_insights_activities = summed_insights_activities.filter { |insight| insight[:engagement_events] > 0 }
          filtered_insights_activities.sort_by { |insight| insight[:engagement_events] }
        end

        sig { returns(T::Array[Copilot::EntityMembership]) }
        memoize def entity_memberships
          Copilot::EntityMembership.where(entity: owner).includes(:copilot_activity).to_a
        end
      end
    end
  end
end
