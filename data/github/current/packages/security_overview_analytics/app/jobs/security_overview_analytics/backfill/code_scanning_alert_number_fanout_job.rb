# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  class Backfill::CodeScanningAlertNumberFanoutJob < BatchedJob
    include GitHub::Memoizer
    include GitHub::SecurityCenter::LoggingHelper
    include FanoutThrottler

    BATCH_SIZE = FanoutThrottler::MAX_ALLOWED_QUEUE_DEPTH

    queue_as :security_overview_analytics_repository_data_cleanup

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    locked_by timeout: 15.minutes, key: ->(job) do
      DEFAULT_LOCK_STRINGIFY_PROC.call([job.class.name])
    end

    around_perform do |_job, block|
      if GitHub.flipper[:security_center_backfill_code_scanning_alert_number].enabled?
        block.call
      else
        clear_lock
      end
    end

    sig do
      override.params(
        args: T.untyped,
        offset_item_id: T.nilable(T.any(Integer, [Integer, Integer])),
        organization_ids: T.nilable(T::Array[Integer]),
        excluded_organization_ids: T.nilable(T::Array[Integer]),
        kwargs: T.untyped
      ).returns(T::Array[[Integer, Integer]])
    end
    def next_batch(*args, offset_item_id: nil, organization_ids: nil, excluded_organization_ids: nil, **kwargs)
      log_timing(step: "next_batch") do
        return [] if offset_item_id.nil?

        # when the job is first queued, the offset_item_id is 0; set it to the new default
        if offset_item_id.is_a?(Integer)
          offset_item_tuple = [0, 0]
        else
          offset_item_tuple = offset_item_id
        end

        rel = ::SecurityOverviewAnalytics::Repository
          .where("(`owner_id`, `repository_id`) > (?, ?)", offset_item_tuple[0], offset_item_tuple[1])
          .order(:owner_id, :owner_type, :repository_id)
          .limit(BATCH_SIZE)

        if organization_ids.present?
          rel = rel.where(owner_id: organization_ids, owner_type: "ORGANIZATION")
        end

        if excluded_organization_ids.present?
          rel = rel.where.not(owner_id: excluded_organization_ids)
        end

        rel.pluck(:owner_id, :repository_id)
      end
    end

    sig do
      override.params(
        org_repo_ids: T::Array[[Integer, Integer]],
        args: T.untyped,
        kwargs: T.untyped
      ).void
    end
    def process_batch(org_repo_ids, *args, **kwargs)
      repo_to_org_lookup = org_repo_ids.to_h { |org_id, repo_id| [repo_id, org_id] }

      log_timing(step: "process_batch") do
        # Make sure we're only queueing jobs for repos with code scanning alerts
        SecurityOverviewAnalytics::CodeScanningAlertRevision
          .where(repository_id: org_repo_ids.map(&:second))
          .distinct # because of the pluck, this will be distinct repository_ids
          .pluck(:repository_id)
          .each do |repo_id|
            Backfill::CodeScanningAlertNumberJob.perform_later(
              repository_id: repo_id,
              organization_id: repo_to_org_lookup[repo_id],
              backfill_mode:
            )
          end
      end
    end

    sig do
      override.params(
        org_repo_ids: T::Array[[Integer, Integer]],
        args: T.untyped,
        kwargs: T.untyped
      ).returns(T.nilable([Integer, Integer]))
    end
    def next_batch_offset_item_id(org_repo_ids, *args, **kwargs)
      org_repo_ids.last
    end

    sig { override.params(args: T.untyped, options: T.untyped).void }
    def finalize_batch(*args, **options)
      clear_lock
    end

    sig { returns(T.nilable(T.any(String, Symbol))) }
    memoize def backfill_mode
      arguments.dig(0, :backfill_mode)
    end

    sig { override.returns(T::Array[T.class_of(ApplicationJob)]) }
    def fanout_jobs
      [Backfill::CodeScanningAlertNumberJob]
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def failbot_context
      super.merge({ app: "github-security-center" })
    end

    sig { override.returns(T::Hash[Symbol, T.untyped]) }
    def logging_context
      kwargs = arguments[0] || {}
      initial_start = kwargs.fetch(:initial_start, Time.current.utc)

      super.merge({
        "gh.batched_job.initial_start": initial_start,
        "gh.batched_job.offset_item_id": kwargs[:offset_item_id],
        "gh.security_overview_analytics.backfill_mode": backfill_mode
      })
    end
  end
end
