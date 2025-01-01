# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityOverviewAnalytics
  module Backfill
    class FanoutBaseJob < BatchedJob
      extend T::Sig
      extend T::Helpers
      include GitHub::SecurityCenter::LoggingHelper
      include FanoutThrottler
      include BatchedJobThrottler

      abstract!

      BATCH_SIZE = FanoutThrottler::MAX_ALLOWED_QUEUE_DEPTH

      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      locked_by timeout: 15.minutes, key: ->(job) do
        DEFAULT_LOCK_STRINGIFY_PROC.call([job.class.name])
      end

      sig do
        override.params(
          args: T.untyped,
          offset_item_id: T.nilable(T.any(Integer, [Integer, Integer])),
          owner_ids: T.nilable(T::Array[Integer]),
          excluded_owner_ids: T.nilable(T::Array[Integer]),
          kwargs: T.untyped
        ).returns(T::Array[[Integer, Integer]])
      end
      def next_batch(*args, offset_item_id: nil, owner_ids: nil, excluded_owner_ids: nil, **kwargs)
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

          if owner_ids.present?
            rel = rel.where(owner_id: owner_ids)
          end

          if excluded_owner_ids.present?
            rel = rel.where.not(owner_id: excluded_owner_ids)
          end

          rel.pluck(:owner_id, :repository_id)
        end
      end

      sig do
        override.params(
          owner_repo_ids: T::Array[[Integer, Integer]],
          args: T.untyped,
          kwargs: T.untyped
        ).returns(T.nilable([Integer, Integer]))
      end
      def next_batch_offset_item_id(owner_repo_ids, *args, **kwargs)
        owner_repo_ids.last
      end

      sig { override.params(args: T.untyped, options: T.untyped).void }
      def finalize_batch(*args, **options)
        clear_lock
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
          "gh.security_overview_analytics.backfill.owner_ids": kwargs[:owner_ids],
          "gh.security_overview_analytics.backfill.excluded_owner_ids": kwargs[:excluded_owner_ids],
        })
      end
    end
  end
end
