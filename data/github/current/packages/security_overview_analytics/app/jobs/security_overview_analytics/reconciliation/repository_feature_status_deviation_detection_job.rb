# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Reconciliation
    class RepositoryFeatureStatusDeviationDetectionJob < BatchedJob
      extend T::Sig
      include GitHub::Memoizer
      include FanoutThrottler

      queue_as :security_overview_analytics_repository_feature_status_deviation_detection

      retry_on_dirty_exit

      use_replicas ApplicationRecord::SecurityOverviewAnalytics,
        ApplicationRecord::Repositories,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Configurations,
        allow_replication_lag: [
          ApplicationRecord::Collab,
          ApplicationRecord::Spokes,
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

        unless Initialization.for(owner).initialized?(type: Initialization::Type::FeatureEnablement)
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
          .where(owner_id: owner_id)
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
        # Orphaned records are expected since we do not remove historical data unless there was offboarding/onboarding.
        return if repository_ids.empty?

        synced_repository_ids = process_synced_repository_feature_status(repository_ids:)
        # Report deviation and queue remediation if any repository missing a feature status record.
        (repository_ids - synced_repository_ids).each do |repository_id|
          report_deviation(repository_id:, deviations: [:missing_owner_repo_data])
          queue_deviation_remediation(repository_id:)
        end
      end

      sig { returns(Reconciliation::Session) }
      memoize def session
        Reconciliation::Session.new(owner_id: owner_id, type: Initialization::Type::FeatureEnablement.serialize)
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

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        [RepositoryFeatureStatusDeviationRemediationJob]
      end

      protected

      sig { override.returns(T::Array[String]) }
      def stats_tags
        [
          "metric_type:feature_enablement",
        ].compact
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.owner.id": :owner_id,
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
        ).returns(T::Array[Integer])
      end
      def process_synced_repository_feature_status(repository_ids:)
        synced_repository_data = T.let(GitHub.dogstats.distribution_time(
          "security_overview_analytics.repository_feature_status_deviation_detection.synced_repository_data.dist",
          tags: all_stats_tags
        ) do
          # Only query the latest revision. A repository without a latest revision is considered data missing.
          FeatureStatusRevision
            .where(repository_id: repository_ids, next_revision_date_id: Date::FUTURE_DATE_ID)
            .includes(:repository)
            .to_a
        end, T::Array[FeatureStatusRevision])

        synced_repository_ids = T.let([], T::Array[Integer])
        GitHub.dogstats.distribution_time(
          "security_overview_analytics.repository_feature_status_deviation_detection.feature_deviation.dist",
          tags: all_stats_tags
        ) do
          synced_repository_data.each do |synced_data|
            repository_id = synced_data.repository_id
            synced_repository_ids << repository_id

            deviations = synced_data.find_deviations
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
        RepositoryFeatureStatusDeviationRemediationJob.perform_later(session_id:, repository_id:)
      end
    end
  end
end
