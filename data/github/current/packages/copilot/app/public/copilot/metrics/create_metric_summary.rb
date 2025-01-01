# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    class CreateMetricSummary < Copilot::Command
      include GitHub::Memoizer

      LOOKBACK_DAYS = 28

      sig { returns(::Organization) }
      attr_reader :owner
      sig { returns(Date) }
      attr_reader :start_date
      sig { returns(Date) }
      attr_reader :end_date

      sig { params(owner: ::Organization, start_date: Date).void }
      def initialize(owner:, start_date:)
        @owner = owner
        @start_date = start_date

        # For now, we only support weekly summaries that start on a Monday and end on a Sunday.
        raise ArgumentError, "start_date must be a Monday" unless start_date.monday?
        @end_date = T.let(start_date + 6.days, Date)
      end

      sig { override.void }
      def perform
        summary = Copilot::MetricSummary.find_or_initialize_by(owner: owner, start_date: start_date, end_date: end_date)

        GitHub.logger.with_named_tags("gh.copilot.owner.id": owner.id, "gh.copilot.owner.type": owner.class.to_s) do
          if summary.persisted?
            GitHub.logger.info("Metric summary already exists, updating")
          else
            GitHub.logger.info("Creating new metric summary")
          end

          summary.assign_attributes(
            total_seats: user_onboarding_aggregator.total_seats,
            active_seats: user_onboarding_aggregator.active_seats,
            inactive_seats: user_onboarding_aggregator.inactive_seats,
            dormant_seats: user_onboarding_aggregator.dormant_seats,
            code_suggestion_events: copilot_activity_aggregator.code_suggestion_events,
            loc_generated: copilot_activity_aggregator.loc_generated,
          )
          if owner.feature_enabled?(:copilot_metric_summaries_m2_fields)
            summary.assign_attributes(
              prs_merged: average_velocity_aggregator.prs_merged,
              pr_lead_times: average_velocity_aggregator.pr_lead_time,
              commit_counts: average_velocity_aggregator.commit_counts,
            )
          end
          Copilot::MetricSummary.throttle_writes_with_retry(max_retry_count: 4) do
            with_write do
              summary.save
            end
          end
        end
      end

      private

      sig { returns(Copilot::Metrics::Aggregators::UserOnboarding) }
      memoize def user_onboarding_aggregator
        Copilot::Metrics::Aggregators::UserOnboarding.new(owner: owner, start_date: start_date)
      end

      sig { returns(Copilot::Metrics::Aggregators::CopilotActivity) }
      memoize def copilot_activity_aggregator
        Copilot::Metrics::Aggregators::CopilotActivity.new(owner: owner, start_date: start_date)
      end

      sig { returns(Copilot::Metrics::Aggregators::AverageVelocity) }
      memoize def average_velocity_aggregator
        Copilot::Metrics::Aggregators::AverageVelocity.new(owner: owner, start_date: start_date)
      end
    end
  end
end
