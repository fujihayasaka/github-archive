# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  module Backfill
    class AlertReopenedAtJob < BatchedJob
      extend T::Sig
      include GitHub::Memoizer
      include GitHub::SecurityCenter::LoggingHelper
      include BatchedJobThrottler

      FEATURES = T.let(%w[code_scanning secret_scanning dependabot], T::Array[String])

      IAlertRevision = T.type_alias do
        T.any(
          DependabotAlertRevision,
          CodeScanningAlertRevision,
          SecretScanningAlertRevision,
        )
      end

      TAlertRevision = T.type_alias do
        T.any(
          T.class_of(DependabotAlertRevision),
          T.class_of(CodeScanningAlertRevision),
          T.class_of(SecretScanningAlertRevision),
        )
      end

      queue_as :security_overview_analytics_on_demand_backfill

      retry_on_dirty_exit
      retry_on_recoverable_exceptions
      retry_on(GitHub::Restraint::UnableToLock, wait: 10.seconds, attempts: 100)

      locked_by timeout: 15.minutes, key: ->(job) do
        feature = job.arguments.dig(0, :feature)
        repository_id = job.arguments.dig(0, :repository_id)
        DEFAULT_LOCK_STRINGIFY_PROC.call([feature, repository_id])
      end

      around_enqueue do |job, block|
        if job.arguments.dig(0, :repository_id).blank? || job.arguments.dig(0, :feature).blank?
          clear_lock
          raise ArgumentError.new("Missing repository_id or feature")
        elsif FEATURES.exclude?(job.arguments.dig(0, :feature))
          clear_lock
          raise ArgumentError.new("Invalid feature")
        end

        block.call
      end

      around_perform do |_job, block|
        if GitHub.flipper[:security_center_backfill_alert_reopened_at].enabled?
          block.call
        end
      end

      sig { override.params(args: T.untyped, kwargs: T.untyped).void }
      def perform(*args, **kwargs)
        log_timing(step: "perform") do
          GitHub::Restraint.new.lock!(T.must(self.class.name), restraint_lock_num_concurrent_jobs, restraint_lock_ttl_sec) do
            super(*T.unsafe(args), **kwargs)
          end
        end
      end

      sig do
        override.params(
          args: T.untyped,
          feature: String,
          repository_id: Integer,
          offset_item_id: T.nilable(T.any(Integer, [Integer, Integer])),
          kwargs: T.untyped
        ).returns(T::Array[IAlertRevision])
      end
      def next_batch(*args, feature:, repository_id:, offset_item_id:, **kwargs)
        log_timing(step: "next_batch") do
          return [] if offset_item_id.nil?

          # when the job is first queued, the offset_item_id is 0; set it to the new default
          if offset_item_id.is_a?(Integer)
            alert_number_offset = 0
            next_revision_date_id_offet = 0
          else
            alert_number_offset, next_revision_date_id_offet = offset_item_id
          end

          model = T.must(feature_model(feature))
          model
            .where(repository_id:)
            .where.not(alert_reopened_at: nil)
            .where("`next_revision_date_id` < ?", Date::FUTURE_DATE_ID)
            .where("(`alert_number`, `next_revision_date_id`) > (?, ?)", alert_number_offset, next_revision_date_id_offet)
            .order(:alert_number, :next_revision_date_id)
            .limit(BATCH_SIZE)
            .to_a
        end
      end

      sig do
        override.params(
          revisions: T::Array[IAlertRevision],
          args: T.untyped,
          feature: String,
          dry_run: T::Boolean,
          kwargs: T.untyped
        ).void
      end
      def process_batch(revisions, *args, feature:, dry_run: false, **kwargs)
        model = T.must(feature_model(feature))

        log_timing(step: "process_batch") do
          revisions.each do |revision|
            repository_id = revision.repository_id
            alert_number = revision.alert_number
            date_id = revision.date_id
            next_revision_date_id = revision.next_revision_date_id
            alert_reopened_at = revision.alert_reopened_at
            alert_resolved = revision.alert_resolved

            if alert_reopened_at.nil?
              log(
                "Alert_reopened_at not found in revision",
                "code.namespace": self.class.name,
                "code.function": __method__,
                "gh.alert.number": alert_number,
                "gh.date.id": date_id
              )
              next
            end

            revisions_updated = 0
            while next_revision = model.find_by(alert_number: alert_number, date_id: next_revision_date_id, repository_id:)
              if next_revision.nil?
                log(
                  "Next revision not found",
                  "code.namespace": self.class.name,
                  "code.function": __method__,
                  "gh.alert.number": alert_number,
                  "gh.date.id": date_id
                )
                break
              end

              # If we encounter another alert with the same or later alert_reopened_at, we stop propagation because it will be handled in
              # a different batch or iteration.
              next_revision_reopened_at = next_revision.alert_reopened_at
              if next_revision_reopened_at && next_revision_reopened_at >= alert_reopened_at
                log(
                  "Stopping propagation. Next revision has a same or later alert_reopened_at",
                  "code.namespace": self.class.name,
                  "code.function": __method__,
                  "gh.alert.number": alert_number,
                  "gh.alert.date_id": next_revision_date_id,
                  "gh.alert.reopened_at": next_revision_reopened_at
                )
                break
              end

              # If current revision is resolved and the next one is unresolved, we treat this as a new reopen.
              if alert_resolved && next_revision_reopened_at.nil? && !next_revision.alert_resolved
                alert_reopened_at = next_revision.alert_updated_at
              end

              if dry_run
                log(
                  "Would update alert_reopened_at",
                  "code.namespace": self.class.name,
                  "code.function": __method__,
                  "gh.alert.number": alert_number,
                  "gh.alert.date_id": next_revision_date_id,
                  "gh.alert.old_reopened_at": next_revision_reopened_at || "nil",
                  "gh.alert.new_reopened_at": alert_reopened_at
                )
              else
                model.throttle_writes_with_retry do
                  next_revision.update!(alert_reopened_at:)
                end
                log(
                  "Updated alert_reopened_at",
                  "code.namespace": self.class.name,
                  "code.function": __method__,
                  "gh.alert.number": alert_number,
                  "gh.alert.date_id": next_revision_date_id,
                  "gh.alert.old_reopened_at": next_revision_reopened_at || "nil",
                  "gh.alert.new_reopened_at": alert_reopened_at
                )
              end
              revisions_updated += 1

              next_revision_date_id = next_revision.next_revision_date_id
              alert_resolved = next_revision.alert_resolved
              if next_revision_date_id == ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID
                log("Stopping propagation. Reached the end of revision chain.")
                break
              end
            end

            log(
              "Finished propagation. Revisions #{dry_run ? "would be updated" : "updated"}.",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.security_overview_analytics.alert_reopened_at_backfill.revisions_updated": revisions_updated
            )
          end
        end
      end

      sig do
        override.params(
          revisions: T::Array[IAlertRevision],
          args: T.untyped,
          kwargs: T.untyped
        ).returns([Integer, Integer])
      end
      def next_batch_offset_item_id(revisions, *args, **kwargs)
        revision = T.must(revisions.last)
        [revision.alert_number, revision.next_revision_date_id]
      end

      sig { override.params(args: T.untyped, options: T.untyped).void }
      def finalize_batch(*args, **options)
        clear_lock
      end

      private

      sig { params(feature: String).returns(T.nilable(TAlertRevision)) }
      def feature_model(feature)
        case feature
        when "code_scanning"
          CodeScanningAlertRevision
        when "secret_scanning"
          SecretScanningAlertRevision
        when "dependabot"
          DependabotAlertRevision
        else
          nil
        end
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({ app: "github-security-center" })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        kwargs = arguments[0] || {}
        owner_id = arguments.dig(0, :owner_id)
        repository_id = arguments.dig(0, :repository_id)
        feature = arguments.dig(0, :feature)
        initial_start = kwargs.fetch(:initial_start, Time.current.utc)

        super.merge({
          "gh.batched_job.initial_start": initial_start,
          "gh.batched_job.offset_item_id": kwargs[:offset_item_id],
          "gh.batched_job.restraint_lock_num_concurrent_jobs": restraint_lock_num_concurrent_jobs,
          "gh.batched_job.restraint_lock_ttl_sec": restraint_lock_ttl_sec,
          "gh.job.restraint_lock.retry.count": exception_executions[[GitHub::Restraint::UnableToLock].to_s] || 0,
          "gh.owner.id": owner_id,
          "gh.repo.id": repository_id,
          "gh.security_overview_analytics.alert_reopened_at_backfill.feature": feature,
        })
      end

      sig { returns(Integer) }
      def restraint_lock_num_concurrent_jobs
        # percentage_of_actors_value ranges from 0.01 to 100
        GitHub
          .flipper["soa_backfill_alert_reopened_at_job_restraint_lock_num_concurrent_jobs".to_sym]
          .percentage_of_actors_value
          .floor
      end

      sig { returns(Integer) }
      def restraint_lock_ttl_sec
        # percentage_of_actors_value ranges from 0.01 to 100
        GitHub
          .flipper["soa_backfill_alert_reopened_at_job_restraint_lock_ttl_minutes".to_sym]
          .percentage_of_actors_value
          .floor
          .minutes
          .to_i
      end
    end
  end
end
