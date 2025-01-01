# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Initialization
      class CodeScanningPullRequestAlertsJob < RepositoryBaseJob # rubocop:disable GitHub/KubeJobsRetryOnDirtyExit
        extend T::Sig

        queue_as :security_overview_analytics_code_scanning_pull_request_alert_initialization

        DEFAULT_BACKFILL_WINDOW_IN_DAYS = 30

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
            .where("merged_at >= ?", backfill_window.days.ago) # merged with in N days
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
          Types::Action::Initialize.serialize
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

        sig { returns(Integer) }
        memoize def backfill_window
          # Long living flag to adjust window of backfill window in production if necessary
          factor_flag = "security_overview_analytics_code_scanning_pull_request_alert_initialization_backfill_window_factor".to_sym
          # percentage_of_actors_value ranges from 0.01 to 100
          session_duration_factor = GitHub.flipper[factor_flag].percentage_of_actors_value
          session_duration_factor = 1 if session_duration_factor == 0
          (DEFAULT_BACKFILL_WINDOW_IN_DAYS * session_duration_factor).floor
        end
      end
    end
  end
end
