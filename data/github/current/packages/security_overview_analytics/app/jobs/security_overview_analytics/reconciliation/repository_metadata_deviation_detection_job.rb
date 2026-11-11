# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Reconciliation
    class RepositoryMetadataDeviationDetectionJob < BatchedJob
      include GitHub::Memoizer
      include FanoutThrottler

      RepositoryMetadata = ::SecurityOverviewAnalytics::Repository

      queue_as :security_overview_analytics_repository_reconciliation

      retry_on_dirty_exit

      use_replicas ApplicationRecord::SecurityOverviewAnalytics,
        ApplicationRecord::Repositories,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Configurations,
        allow_replication_lag: [
          ApplicationRecord::Collab
        ]

      NON_RETRYABLE_EXCEPTIONS = T.let([
        StandardError,
      ], T::Array[T::Class[T.anything]])

      RETRYABLE_EXCEPTIONS = T.let([
        Freno::Error,
        *Resiliency::Response::UnavailableExceptions, # DB unavailable
      ], T::Array[T::Class[T.anything]])

      # Custom retry for recoverable exceptions. Reset session lock if attempts are exhausted.
      RETRYABLE_EXCEPTIONS.each do |error_class|
        retry_on error_class, wait: :polynomially_longer, attempts: 5 do |job, error|
          last_session_started_at = job.arguments.first&.dig(:last_session_started_at)
          job.session.reset!(last_session_started_at:)

          GitHub.dogstats.increment("security_overview_analytics.reconciliation.abort",
            tags: job.all_stats_tags + [
              "cause:stopped_retry",
              "error:#{error.class.name.underscore}"
            ]
          )
        end
      end

      around_enqueue do |job, block|
        organization_id = job.arguments.dig(0, :organization_id)
        owner_id = job.arguments.dig(0, :owner_id)
        if organization_id.blank? && owner_id.blank?
          clear_lock
          raise ArgumentError.new("Missing organization_id and owner_id.")
        end

        session_started_at = job.arguments.first&.dig(:session_started_at)
        if session_started_at.nil? && session.locked?
          # A new job should bail if there's already one running or if it's still
          # within the cooldown period.
          report_reconciliation_skipped("session_locked")
          clear_lock
          next
        elsif session_started_at.nil?
          # If session is free, initiate a new one
          job.arguments.first.merge!(session.lock!)
        end

        block.call
      end

      around_perform do |job, block|
        if !session.locked?
          # This means the session has been reset and should no longer continue.
          report_reconciliation_skipped("session_reset")
          next
        end

        # If the job fails any tenant validation, report, reset session, and skip.
        unless TenantValidationHelper.is_owner_in_scope?(owner)
          report_reconciliation_skipped("owner_not_in_scope", reset: true)
          next
        end

        unless Initialization.for(owner).initialized?(type: Initialization::Type::RepositoryMetadata)
          report_reconciliation_skipped("tenant_not_initialized", reset: true)
          next
        end

        # Proceed with the batch
        block.call

      rescue *RETRYABLE_EXCEPTIONS
        raise
      rescue *NON_RETRYABLE_EXCEPTIONS => e
        # Reset session and report error
        session.reset!(last_session_started_at:)
        GitHub.dogstats.increment("security_overview_analytics.reconciliation.abort",
          tags: job.all_stats_tags + [
            "cause:stopped_retry",
            "error:#{e.class.name&.underscore}"
          ]
        )

        raise
      end

      sig do
        override.params(
          args: T.untyped,
          offset_item_id: Integer,
          kwargs: T.untyped,
        )
        .returns(T::Array[Integer])
      end
      def next_batch(*args, offset_item_id:, **kwargs)
        ::Repository
          .where(owner_id:)
          .where("id > ?", offset_item_id)
          .active
          .order(:id)
          .limit(BATCH_SIZE)
          .pluck(:id)
      end

      sig do
        override.params(
          repository_ids: T::Array[Integer],
          args: T.untyped,
          offset_item_id: Integer,
          kwargs: T.untyped,
        ).void
      end
      def process_batch(repository_ids, *args, offset_item_id:, **kwargs)
        process_orphaned_repository_metadata(repository_ids:, offset_item_id:)

        # With orphaned records handled, bail out if no repository found in batch.
        return if repository_ids.empty?

        synced_repository_ids = process_synced_repository_metadata(repository_ids:)
        # Report deviation and queue remediation if any repository missing a metadata record.
        (repository_ids - synced_repository_ids).each do |repository_id|
          report_deviation(repository_id:, deviations: [:missing_owner_repo_metadata])
          queue_deviation_remediation(repository_id:)
        end
      end

      sig do
        override.params(
          repository_ids: T::Array[Integer],
          args: T.untyped,
          kwargs: T.untyped
        ).returns(T.nilable(Integer))
      end
      def next_batch_offset_item_id(repository_ids, *args, **kwargs)
        # Ids are sorted in ascending order thus last id is the largest
        repository_ids.last
      end

      sig { returns(Reconciliation::Session) }
      memoize def session
        Reconciliation::Session.new(owner_id: owner_id, type: Initialization::Type::RepositoryMetadata.serialize)
      end

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        [RepositoryMetadataDeviationRemediationJob]
      end

      protected

      sig { override.returns(T::Array[String]) }
      def stats_tags
        [
          "metric_type:repository_metadata",
        ].compact
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.owner.id": arguments.dig(0, :owner_id),
          "gh.security_overview_analytics.job.session_id": session_id,
          "gh.security_overview_analytics.job.session_started_at": arguments.dig(0, :session_started_at),
          "gh.security_overview_analytics.job.last_session_started_at": arguments.dig(0, :last_session_started_at),
          "gh.security_overview_analytics.job.offset_item_id": arguments.dig(0, :offset_item_id),
          "gh.security_overview_analytics.job.progress": arguments.dig(0, :progress),
        })
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def failbot_context
        super.merge({
          app: "github-security-center"
        })
      end

      private

      sig { returns(T.nilable(Time)) }
      memoize def last_session_started_at
        (arguments[0] || {}).fetch(:last_session_started_at, nil)
      end

      sig { returns(T.nilable(Time)) }
      memoize def session_started_at
        (arguments[0] || {}).fetch(:session_started_at, nil)
      end

      sig { returns(String) }
      memoize def session_id
        session.id
      end

      sig { returns(Integer) }
      memoize def owner_id
        (arguments[0] || {}).fetch(:owner_id, nil) || (arguments[0] || {}).fetch(:organization_id, nil)
      end

      sig { returns(::User) }
      memoize def owner
        ::User.find(owner_id)
      end

      sig { params(reason: String, reset: T::Boolean).void }
      def report_reconciliation_skipped(reason, reset: false)
        # If required, reset session lock to the previous session run
        session.reset!(last_session_started_at:) if reset

        GitHub.logger.info(
          "Reconciliation skipped.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.security_overview_analytics.job.reason": reason,
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.reconciliation.skipped",
          tags: all_stats_tags + [
            "reason:#{reason.parameterize.underscore}"
          ]
        )
      end

      sig do
        params(
          repository_ids: T::Array[Integer],
          offset_item_id: Integer
        ).void
      end
      def process_orphaned_repository_metadata(repository_ids:, offset_item_id:)
        is_last_batch = !has_next_batch?(repository_ids)
        tags = all_stats_tags + ["is_last_batch:#{is_last_batch}"]

        # Orphaned repository metadata means the record has the same owner_id
        # while its repository_id no longer belongs to the same org.
        #
        # Orphaned records can exist:
        # 1. within the same range of the current batch
        # 2. beyond the last batch of the same organization (> max(repository_id))

        GitHub.dogstats.distribution_time(
          "security_overview_analytics.repository_metadata_deviation_detection.orphaned_repo_metadata.dist", tags:
        ) do
          rel = RepositoryMetadata
            .where("repository_id > ?", offset_item_id)

          if owner.organization?
            # Back-compat to keep supporting organization queries
            # TODO: remove when switching to using owner_id
            rel = rel.where(organization_id: owner_id)
          else
            # We are assuming that for enterprises kicking this job off the data is migrated to contain values in owner_id and owner_type columns
            rel = rel.where(owner_id:, owner_type: owner.type)
          end

          if repository_ids.any?
            rel = rel.where.not(repository_id: repository_ids)
            rel = rel.where("repository_id <= ?", repository_ids.last) unless is_last_batch
          end

          orphaned_repository_ids = T.let(rel.pluck(:repository_id), T::Array[Integer])
          orphaned_repository_ids.each do |repository_id|
            report_deviation(repository_id:, deviations: [:orphaned_repo_metadata])
            queue_deviation_remediation(repository_id:)
          end

          # Orphaned metadata records are rare thus we don't anticipate that we can have as many orphaned records
          # as the batch size in production. Log telemetry in case the reality breaks our assumption.
          if orphaned_repository_ids.size >= BATCH_SIZE
            GitHub.logger.info(
              "High orphaned repository metadata count.",
              "code.namespace": self.class.name,
              "code.function": __method__,
              "gh.security_overview_analytics.job.orphaned_repositories_count": orphaned_repository_ids.size,
              "gh.security_overview_analytics.job.is_last_batch": is_last_batch,
              "gh.security_overview_analytics.job.is_empty_batch": repository_ids.empty?
            )
            GitHub.dogstats.increment(
              "security_overview_analytics.repository_metadata_deviation_detection.high_orphaned_metadata_count", tags:
            )
          end
        end
      end

      sig do
        params(
          repository_ids: T::Array[Integer],
        ).returns(T::Array[Integer])
      end
      def process_synced_repository_metadata(repository_ids:)
        synced_repository_metadata = T.let(GitHub.dogstats.distribution_time(
          "security_overview_analytics.repository_metadata_deviation_detection.synced_repository_metadata.dist",
          tags: all_stats_tags
        ) do
          rel = RepositoryMetadata
            .where(repository_id: repository_ids)
            .includes(:repository)

          if owner.organization?
            # Back-compat to keep supporting organization queries
            # TODO: remove when switching to using owner_id
            rel = rel.where(organization_id: owner_id)
          else
            # We are assuming that for enterprises kicking this job off the data is migrated to contain values in owner_id and owner_type columns
            rel = rel.where(owner_id:, owner_type: owner.type)
          end

          rel.to_a
        end, T::Array[RepositoryMetadata])

        synced_repository_ids = T.let([], T::Array[Integer])
        GitHub.dogstats.distribution_time(
          "security_overview_analytics.repository_metadata_deviation_detection.field_deviation.dist",
          tags: all_stats_tags
        ) do
          synced_repository_metadata.each do |synced_metadata|
            repository_id = synced_metadata.repository_id
            synced_repository_ids << repository_id

            deviations = synced_metadata.fields_with_deviation
            next unless deviations.any?

            report_deviation(repository_id:, deviations:)
            queue_deviation_remediation(repository_id:)
          end
        end

        synced_repository_ids
      end

      sig do
        params(
          repository_id: Integer,
          deviations: T::Array[Symbol]
        ).void
      end
      def report_deviation(repository_id:, deviations:)
        GitHub.logger.info(
          "Deviation found.",
          "code.namespace": self.class.name,
          "code.function": __method__,
          "gh.repo.id": repository_id,
          "gh.security_overview_analytics.deviations": deviations
        )
        GitHub.dogstats.increment(
          "security_overview_analytics.reconciliation.deviation",
          tags: all_stats_tags + [*deviations.map { |d| "deviation:#{d}" }]
        )
      end

      sig { params(repository_id: Integer).void }
      def queue_deviation_remediation(repository_id:)
        RepositoryMetadataDeviationRemediationJob.perform_later(session_id:, repository_id:)
      end
    end
  end
end
