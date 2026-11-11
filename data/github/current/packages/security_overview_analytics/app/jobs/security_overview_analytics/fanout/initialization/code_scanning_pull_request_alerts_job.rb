# typed: strict
# frozen_string_literal: true

module SecurityOverviewAnalytics
  module Fanout
    module Initialization
      class CodeScanningPullRequestAlertsJob < RepositoryBaseJob # rubocop:disable GitHub/KubeJobsRetryOnDirtyExit

        queue_as :security_overview_analytics_code_scanning_pull_request_alert_initialization

        LOOKBACK_WINDOW_IN_DAYS = 90

        class BatchItem < T::Struct

          const :merged_at, Time
          const :id, Integer

          sig { returns(String) }
          def to_s
            JSON.dump(self.serialize)
          end

          sig { params(value: String).returns(T.attached_class) }
          def self.from_string(value)
            JSON.parse(value).symbolize_keys => { merged_at:, id: }
            new(
              merged_at: Time.parse(merged_at),
              id:,
            )
          end
        end

        sig do
          override
            .params(
              args: T.untyped,
              offset_item_id: T.nilable(T.any(String, Integer)),
              kwargs: T.untyped,
            )
            .returns(T::Array[BatchItem])
        end
        def next_batch(*args, offset_item_id:, **kwargs)
          cursor = \
            if offset_item_id.is_a?(String)
              BatchItem.from_string(offset_item_id)
            else
              # If this is the first job in the sequence, filter by watermark date.
              # merged with in N days
              BatchItem.new(merged_at: LOOKBACK_WINDOW_IN_DAYS.days.ago, id: 0)
            end

          query = ::PullRequest
            .optimizer_hints("JOIN_FIXED_ORDER()")
            .from(
              "`#{::PullRequest.table_name}` USE INDEX(`index_pull_requests_on_repository_id_and_merged_at`)"
            )
            .joins(%{
              INNER JOIN `#{::PullRequest.table_name}` AS `right`
              ON `right`.`id` = `#{::PullRequest.table_name}`.`id`
              AND `right`.`repository_id` = `right`.`base_repository_id`
            }.squish)
            .where("`right`.`base_ref` = CAST(? AS Binary)", repository&.default_branch)
            .where(repository_id:) # this is necessary to perform index sort
            .where(%{
              (
                `#{::PullRequest.table_name}`.`merged_at`,
                `#{::PullRequest.table_name}`.`id`
              ) > (?, ?)}.squish,
              cursor.merged_at,
              cursor.id,
            )
            .order(:merged_at, :id)
            .limit(BATCH_SIZE)
            .select(:merged_at, :id)

          ::PullRequest.connection.select_all(query)
            .map { |row| BatchItem.new(**row.to_hash.symbolize_keys) }
        end

        sig do
          override
            .params(
              batch: T::Array[BatchItem],
              args: T.untyped,
              kwargs: T.untyped,
            )
            .void
        end
        def process_batch(batch, *args, **kwargs)
          batch.each do |item|
            CodeScanningPullRequestAlertsIngestionJob.perform_later(pull_request_id: item.id, source_event:)
          end
        end

        sig do
          override
            .params(
              batch: T::Array[BatchItem],
              args: T.untyped,
              kwargs: T.untyped,
            )
            .returns(T.nilable(T.any(String, Integer)))
        end
        def next_batch_offset_item_id(batch, *args, **kwargs)
          batch.last&.to_s
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
      end
    end
  end
end
