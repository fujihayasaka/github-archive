# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  class CodeScanningPullRequestAlertsIngestionJob < ApplicationJob
    include GitHub::Memoizer

    queue_as :security_overview_analytics_code_scanning_pull_request_alert_ingestion

    locked_by timeout: 15.minutes, key: ->(job) do
      pull_request_id = job.arguments.dig(0, :pull_request_id)
      DEFAULT_LOCK_STRINGIFY_PROC.call([pull_request_id])
    end

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    RETRYABLE_ERRORS = T.let([
      ActiveRecord::Deadlocked, # Data writes
      ::SecurityProduct::PullRequestAlert::TurboscanApiError # API errors
    ], T::Array[T.class_of(StandardError)])
    # Workaround for https://sorbet.org/docs/error-reference#7019
    T.unsafe(self).retry_on *RETRYABLE_ERRORS, wait: :polynomially_longer

    resolve_tenant_context do |args|
      pull_request_id = args[:pull_request_id]
      pull_request = ::PullRequest.find_by(id: pull_request_id)
      ::Repositories::Public.resolve_tenant(id: pull_request&.repository_id)
    end

    around_perform do |_, block|
      next unless should_perform?
      block.call
      GitHub.dogstats.increment("security_overview_analytics.code_scanning_pull_request_alert_ingestion.processed", tags: all_stats_tags)
    end

    sig do
      params(
        pull_request_id: Integer,
        source_event: String
      ).void
    end
    def perform(pull_request_id:, source_event:)
      alerts_payload = get_pull_request_alerts.map do |alert|
        CodeScanningPullRequestAlert::UpdatePayload.from_pull_request_alert(
          pull_request: T.must(pull_request),
          alert:,
          source_event:
        )
      end
      return unless alerts_payload.present?

      # Reconciliation only step
      alerts_with_deviations = find_and_report_alert_deviations(alerts_payload) if is_reconciliation?

      # Note:
      # - Instead of insert/update in batches, upsert one record at a time to avoid spiking replication latency
      # - Turboscan API returns no more than 100 alerts
      GitHub.dogstats.distribution_time(
        "security_overview_analytics.code_scanning_pull_request_alert_ingestion.upsert.dist",
        tags: all_stats_tags
      ) do
        # Does update alert fixed/resolution state for existing record.
        # Xref: https://github.com/github/security-center/issues/5830#issuecomment-2286912275
        update_except = %w[alert_resolved alert_resolution alert_resolved_at]

        alerts_payload.each do |payload|
          # Reconciliation only step
          if is_reconciliation? &&
            (alerts_with_deviations.blank? ||
            !alerts_with_deviations.include?(payload.alert_number))
            # Avoid data change if deviation not found for reconciliation
            next
          end

          CodeScanningPullRequestAlert.throttle_writes_with_retry do
            CodeScanningPullRequestAlert.upsert(payload, update_except:, force_rewrite: is_reconciliation?)
          end
        end
      end
    end

    protected

    sig { override.returns(T::Array[String]) }
    def stats_tags
      tags = super
      tags << "source_event:#{source_event}"
      tags
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      super.merge({
        "gh.repo.id": repository&.id,
        "gh.owner.id": repository&.owner&.id,
        "gh.pull_request.id": pull_request_id,
        "gh.pull_request.merged_at": pull_request&.merged_at,
        "gh.security_overview_analytics.source_event": source_event
      })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({
        app: "github-security-center"
      })
    end

    sig { returns(Integer) }
    memoize def pull_request_id
      arguments.dig(0, :pull_request_id) || 0
    end

    sig { returns(T.nilable(::PullRequest)) }
    memoize def pull_request
      ::PullRequest.find_by(id: pull_request_id)
    end

    sig { returns(T.nilable(::Repository)) }
    memoize def repository
      return nil unless pull_request.present?
      ::Repositories::Public.find_active(pull_request&.repository_id)
    end

    sig { returns(String) }
    memoize def source_event
      arguments.dig(0, :source_event)
    end

    sig { returns(T::Boolean) }
    memoize def is_reconciliation?
      Fanout::Types::Action.try_deserialize(source_event) == Fanout::Types::Action::Reconcile
    end

    sig { returns(T::Boolean) }
    def should_perform?
      unless pull_request.present?
        log_ingestion_stopped(:pull_request_not_found)
        return false
      end

      unless repository.present?
        log_ingestion_stopped(:repository_not_found)
        return false
      end

      unless TenantValidationHelper.should_handle_code_scanning_pull_request_alert?(T.must(repository).owner)
        log_ingestion_stopped(:ineligible_repo_owner)
        return false
      end

      unless repository&.code_scanning_usable?
        log_ingestion_stopped(:code_scanning_unavailable)
        return false
      end

      unless repository&.turboscan_considers_code_scanning_enabled?
        log_ingestion_stopped(:code_scanning_disabled)
        return false
      end

      repo_default_branch = repository&.default_branch
      pull_request_base_ref = pull_request&.base_ref_name
      unless repo_default_branch == pull_request_base_ref
        GitHub.logger.with_named_tags(
          "gh.repo.default_branch": repo_default_branch,
          "gh.pull_request.base_ref.name": pull_request_base_ref,
        ) do
          log_ingestion_stopped(:not_default_branch_based)
        end
        return false
      end

      unless pull_request&.repository_id == pull_request&.base_repository_id
        log_ingestion_stopped(:advisory_workspace_pull_request)
        return false
      end

      unless pull_request&.merged?
        log_ingestion_stopped(:pull_request_not_merged)
        return false
      end

      true
    end

    sig { params(reason: Symbol).void }
    def log_ingestion_stopped(reason)
      GitHub.logger.info(
        "Pull request alert ingestion stopped.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.reason": "reason"
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.code_scanning_pull_request_alert_ingestion.stopped",
        tags: all_stats_tags + ["reason:#{reason}"]
      )
    end

    private

    sig do
      returns(T::Array[::SecurityProduct::PullRequestAlert])
    end
    memoize def get_pull_request_alerts
      alerts = ::SecurityProduct::PullRequestAlert.codeql_introduced_alerts(T.must(pull_request))

      GitHub.logger.info(
        "Found pull request alerts.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.alerts.count": alerts.size,
        "gh.security_overview_analytics.alerts": alerts.map(&:alert_number).inspect
      )
      GitHub.dogstats.distribution(
        "security_overview_analytics.code_scanning_pull_request_alert_ingestion.alert_count.dist",
        alerts.size,
        tags: all_stats_tags
      )

      alerts
    end

    sig do
      params(
        alerts_payload: T::Array[CodeScanningPullRequestAlert::UpdatePayload]
      ).returns(T::Set[Integer])
    end
    def find_and_report_alert_deviations(alerts_payload)
      return [].to_set if alerts_payload.empty?

      GitHub.dogstats.distribution_time(
        "security_overview_analytics.code_scanning_pull_request_alert_ingestion.report_deviation.dist",
        tags: all_stats_tags
      ) do
        # Context: current max alerts count from Turboscan API is 1000
        payloads_by_alert_number = alerts_payload.index_by(&:alert_number)
        incoming_alert_numbers = T.let(payloads_by_alert_number.keys, T::Array[Integer])

        base_rel = CodeScanningPullRequestAlert.where(
          repository_id: T.must(pull_request).repository_id,
          pull_request_id: pull_request&.id
        )
        existing_alert_numbers = T.let(base_rel.pluck(:alert_number), T::Array[Integer])

        # Missing alerts:
        missing_alerts = incoming_alert_numbers - existing_alert_numbers
        missing_alerts.each do |number|
          report_alert_deviation(alert_number: number, deviations: [:missing_alert])
        end

        # Orphaned alerts:
        # Since this is an unlikely event and for resiliency purpose, we only
        # observe and log telemetry when orphaned alerts are found
        orphaned_alerts = existing_alert_numbers - incoming_alert_numbers
        orphaned_alerts.each do |number|
          report_alert_deviation(alert_number: number, deviations: [:orphaned_alert])
        end

        alerts_to_update = incoming_alert_numbers & existing_alert_numbers
        return missing_alerts.to_set if alerts_to_update.empty?

        alerts_with_deviations = missing_alerts
        base_rel.where(alert_number: alerts_to_update).to_a.each do |alert|
          payload = payloads_by_alert_number[alert.alert_number]
          next if payload.nil?

          deviations = alert.fields_with_deviation(payload)
          if deviations.present?
            report_alert_deviation(alert_number: alert.alert_number, deviations:)
            alerts_with_deviations << alert.alert_number
          end
        end

        alerts_with_deviations.to_set
      end
    end

    sig { params(alert_number: Integer, deviations: T::Array[Symbol]).void }
    def report_alert_deviation(alert_number:, deviations:)
      GitHub.logger.info(
        "Alert deviation found.",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.security_overview_analytics.alert_number": alert_number,
        "gh.security_overview_analytics.deviations": deviations.inspect
      )
      GitHub.dogstats.increment(
        "security_overview_analytics.code_scanning_pull_request_alert_ingestion.deviation",
        tags: all_stats_tags + [
          *deviations.map { |d| "deviation:#{d}" }
        ]
      )
    end
  end
end
