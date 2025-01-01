# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Reconciliation
    class DependabotRepositoriesDeviationDetectionJob < BatchedJob
      include GitHub::Memoizer
      include FanoutThrottler
      include BatchedJobThrottler

      RepositoryMetadata = ::SecurityOverviewAnalytics::Repository

      queue_as :security_overview_analytics_dependabot_repositories_deviation_detection

      retry_on_dirty_exit

      use_replicas ApplicationRecord::SecurityOverviewAnalytics,
        ApplicationRecord::Repositories,
        ApplicationRecord::Mysql1,
        ApplicationRecord::Mysql5,
        ApplicationRecord::Configurations

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
              "reason:stopped_retry",
              "error:#{error.class.name.underscore}"
            ]
          )
        end
      end

      around_enqueue do |job, block|
        organization_id = job.arguments.dig(0, :organization_id)
        if organization_id.blank?
          clear_lock
          raise ArgumentError.new("Missing organization_id.")
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
        unless SecurityCenter::SecurityFeatures.dependabot_alerts_enabled_for_instance?
          report_reconciliation_skipped("feature_unavailable", reset: true)
          next
        end

        unless TenantValidationHelper.is_owner_in_scope?(organization)
          report_reconciliation_skipped("owner_not_in_scope", reset: true)
          next
        end

        unless Initialization.for(organization).initialized?(type: Initialization::Type::DependabotAlerts)
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
            "reason:stopped_retry",
            "error:#{e.class.name&.underscore}"
          ]
        )

        raise
      end

      sig do
        override.params(
          args: T.untyped,
          organization_id: Integer,
          offset_item_id: Integer,
          kwargs: T.untyped,
        )
        .returns(T::Array[Integer])
      end
      def next_batch(*args, organization_id:, offset_item_id:, **kwargs)
        ::Repository
          .where(active: true, owner_id: organization_id)
          .where(::Repository.arel_table[:id].gt(offset_item_id))
          .order(:id)
          .limit(BATCH_SIZE)
          .pluck(:id)
      end

      sig do
        override.params(
          repository_ids: T::Array[Integer],
          args: T.untyped,
          organization_id: Integer,
          offset_item_id: Integer,
          kwargs: T.untyped,
        )
        .void
      end
      def process_batch(repository_ids, *args, organization_id:, offset_item_id:, **kwargs)
        # Orphaned repositories are not handled by alerts reconciliation since revision table does not track repository owners.
        # They will be cleaned up by RepositoryDataCleanupJob
        return if repository_ids.empty?

        tracked_repository_ids = T.let(DependabotAlertRevision
          .where(repository_id: repository_ids)
          .select(:repository_id).distinct
          .pluck(:repository_id), T::Array[Integer])

        # For repos that already have revisions, schedule a reconciliation to cover the period since the last one.
        tracked_repository_ids.each do |repository_id|
          DependabotAlertsDeviationDetectionJob.perform_later(repository_id:, last_session_started_at:)
        end

        # For any repos that do not have any revisions, there are two possibilities
        #  - we're missing all alert data for the repo
        #  - the repo legitimately doesn't have any alerts
        # Either way, attempt to reconcile.
        (repository_ids - tracked_repository_ids).each do |repository_id|
          DependabotAlertsDeviationDetectionJob.perform_later(
            repository_id:,
            last_session_started_at: nil, # Force a full scan reconciliation
          )
        end
      end

      sig do
        override.params(
          batch: T::Array[Integer],
          args: T.untyped,
          kwargs: T.untyped,
        )
        .returns(T.nilable(Integer))
      end
      def next_batch_offset_item_id(batch, *args, **kwargs)
        batch.max
      end

      sig { returns(Reconciliation::Session) }
      memoize def session
        Reconciliation::Session.new(owner_id: organization_id, type: Initialization::Type::DependabotAlerts.serialize)
      end

      sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
      def fanout_jobs
        # If any of the below job queue is being throttled, delay the entire batch.
        [
          DependabotAlertsDeviationDetectionJob,
          Initialization::Repositories::DependabotAlertsJob,
        ]
      end

      protected

      sig { override.returns(T::Array[String]) }
      def stats_tags
        [
          "metric_type:dependabot_alerts",
        ].compact
      end

      sig { override.returns(T::Hash[Symbol, T.untyped]) }
      def logging_context
        super.merge({
          "gh.org.id": organization_id,
          "gh.org.login": organization.display_login,
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

      sig { returns(Integer) }
      memoize def organization_id
        (arguments[0] || {}).fetch(:organization_id)
      end

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

      sig { returns(::Organization) }
      memoize def organization
        ::Organization.find(organization_id)
      end
    end
  end
end
