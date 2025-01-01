# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    class BatchedSummaryJob < BatchedJob
      locked_by timeout: 10.minutes, key: DEFAULT_LOCK_PROC
      retry_on_dirty_exit
      retry_on_recoverable_exceptions
      queue_as :copilot

      BATCH_SIZE = 10

      sig { void }
      def self.perform_backfill
        oldest_allowable_date = Date.current - SummaryJob::SUMMARY_RETENTION_DAYS.days
        newest_allowable_date = Date.current - 7.days
        dates = (oldest_allowable_date..newest_allowable_date).select(&:monday?).map(&:to_s)

        perform_later(start_dates: dates)
      end

      sig do
        params(
          batch: T::Array[Integer],
          args: T.untyped, # rubocop:disable Sorbet/ForbidTUntyped
          start_dates: T::Array[String],
          kwargs: T.untyped # rubocop:disable Sorbet/ForbidTUntyped
        ).void
      end
      def process_batch(batch, *args, start_dates:, **kwargs)
        if GitHub.flipper[:copilot_metrics_batched_summary_job].enabled?
          orgs = ::Organization.where(id: batch).to_a
          orgs.each do |org|
            process_organization(org, start_dates)
          end
        else
          GitHub.logger.info("Skipping Copilot::Metrics::BatchedSummaryJob because the feature flag is disabled. "\
            "Would have processed #{batch.size} organizations with ids spanning #{batch.first} to #{batch.last} "\
            "and start_dates: #{start_dates}.")
        end
      end

      sig do
        params(
          args: T.untyped, # rubocop:disable Sorbet/ForbidTUntyped
          timestamp: Time,
          offset_item_id: Integer,
          progress: Integer,
          kwargs: T.untyped # rubocop:disable Sorbet/ForbidTUntyped
        ).returns(T::Array[Integer])
      end
      def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **kwargs)
        Copilot::Seat
          .where.not(organization_id: nil)
          .where("organization_id > ?", offset_item_id)
          .limit(BATCH_SIZE)
          .order(organization_id: :asc)
          .distinct
          .pluck(:organization_id)
      end

      sig do
        params(
          batch: T::Array[Integer],
          args: T.untyped, # rubocop:disable Sorbet/ForbidTUntyped
          kwargs: T.untyped # rubocop:disable Sorbet/ForbidTUntyped
        ).returns(T.nilable(Integer))
      end
      def next_batch_offset_item_id(batch, *args, **kwargs)
        batch.last if batch.any?
      end

      private

      sig { params(org: ::Organization, start_dates: T::Array[String]).void }
      def process_organization(org, start_dates)
        GitHub.logger.with_named_tags("gh.copilot.owner.id": org.id, "gh.copilot.owner.type": org.class.to_s) do
          GitHub.logger.info("Processing #{start_dates.size} date(s) for organization #{org.id}")

          start_dates.each do |date_str|
            begin
              date = Date.parse(date_str)
              raise ArgumentError, "start_date must be a Monday" unless date.monday?

              Copilot::Metrics::CreateMetricSummary.call(owner: org, start_date: date)
            rescue StandardError => e # rubocop:disable Lint/GenericRescue
              GitHub.logger.error("Failed to process start_date #{date_str} for org #{org.id}: #{e.message}")
            end
          end

          delete_old_summaries(owner: org)
        end
      end

      sig { params(owner: ::Organization).void }
      def delete_old_summaries(owner:)
        to_delete = Copilot::MetricSummary.where(owner: owner).where("start_date < ?", SummaryJob::SUMMARY_RETENTION_DAYS.days.ago)

        if to_delete.any?
          GitHub.logger.info("Deleting #{to_delete.count} metric summaries for organization #{owner.id}")
          with_write do
            to_delete.destroy_all
          end
        else
          GitHub.logger.info("No summaries to delete for organization #{owner.id}")
        end
      end
    end
  end
end
