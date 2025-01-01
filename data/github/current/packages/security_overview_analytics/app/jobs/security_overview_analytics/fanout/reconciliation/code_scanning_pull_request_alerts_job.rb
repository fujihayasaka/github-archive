# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Reconciliation
      class CodeScanningPullRequestAlertsJob < RepositoryBaseJob # rubocop:disable GitHub/KubeJobsRetryOnDirtyExit
        extend T::Sig

        queue_as :security_overview_analytics_code_scanning_pull_request_alert_reconciliation

        DEFAULT_LOOKBACK_WINDOW_IN_DAYS = 30

        sig do
          override.params(
            args: T.untyped,
            offset_item_id: Integer,
            kwargs: T.untyped,
          )
          .returns(T::Array[Integer])
        end
        def next_batch(*args, offset_item_id:, **kwargs)
          ::PullRequest
            .where(repository_id:)
            .where(base_repository_id: repository_id) # exclude PRs from advisory workspace
            .where(base_ref: repository&.default_branch) # base off default branch
            .where(::PullRequest.arel_table[:id].gt(offset_item_id))
            .where("merged_at >= ?", merged_since)
            .order(:id)
            .limit(BATCH_SIZE)
            .pluck(:id)
        end

        sig do
          override.params(
            pull_request_ids: T::Array[Integer],
            args: T.untyped,
            kwargs: T.untyped,
          ).void
        end
        def process_batch(pull_request_ids, *args, **kwargs)
          # Pull request is a mean for us to know whether we should look for alerts
          # and the existance of a merged pull request does not change the fact if
          # an alert was introduced or prevented.
          # For the above reason, we do not handle orphaned pull requests during
          # reconciliation.
          pull_request_ids.each do |id|
            CodeScanningPullRequestAlertsIngestionJob.perform_later(pull_request_id: id, source_event:)
          end
        end

        sig do
          override.params(
            pull_request_ids: T::Array[Integer],
            args: T.untyped,
            kwargs: T.untyped,
          )
          .returns(T.nilable(Integer))
        end
        def next_batch_offset_item_id(pull_request_ids, *args, **kwargs)
          pull_request_ids.last
        end

        sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
        def fanout_jobs
          [CodeScanningPullRequestAlertsIngestionJob]
        end

        protected

        sig { override.returns(String) }
        memoize def source_event
          Fanout::Types::Action::Reconcile.serialize
        end

        sig { override.returns(T::Boolean) }
        def should_perform?
          return false unless super

          unless TenantValidationHelper.should_handle_code_scanning_pull_request_alert?(repository&.owner)
            log_fanout_stopped(:ineligible_repo_owner)
            return false
          end

          unless repository&.code_scanning_usable?
            log_fanout_stopped(:code_scanning_unavailable)
            return false
          end

          unless repository&.turboscan_considers_code_scanning_enabled?
            log_fanout_stopped(:code_scanning_disabled)
            return false
          end

          true
        end

        private

        sig { returns(Time) }
        memoize def merged_since
          earliest_merged_at = lookback_window.days.ago.iso8601(3).to_time.utc
          target_merged_at = last_session_locked_at || earliest_merged_at
          return target_merged_at if target_merged_at >= earliest_merged_at
          earliest_merged_at
        end

        sig { returns(Integer) }
        memoize def lookback_window
          # Long living flag to adjust window of lookback window in production if necessary
          factor_flag = "security_overview_analytics_code_scanning_pull_request_alert_reconciliation_lookback_window_factor".to_sym
          # percentage_of_actors_value ranges from 0.01 to 100
          session_duration_factor = GitHub.flipper[factor_flag].percentage_of_actors_value
          session_duration_factor = 1 if session_duration_factor == 0
          (DEFAULT_LOOKBACK_WINDOW_IN_DAYS * session_duration_factor).floor
        end
      end
    end
  end
end
