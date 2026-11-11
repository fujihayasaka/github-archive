# typed: strict
# frozen_string_literal: true

module Copilot
  # BatchedJob that finds users with expired student coupons and active
  # Copilot subscription items, then enqueues a per-user
  # SubscriptionItemExpiredCheckJob for each.
  #
  # All JOINs stay within the billing cluster (coupon_redemptions, coupons,
  # plan_subscriptions, subscription_items). User IDs are plucked and the
  # per-user job loads the User record itself.
  class ExpiredStudentBatchedJob < BatchedJob
    include Copilot::Helpers

    retry_on_dirty_exit
    queue_as :copilot_edu_user_deactivation_job
    exempt_from_tenant_context_requirement

    BATCH_SIZE = 100
    QUERY_LIMIT = 10_000

    around_perform do |_job, block|
      with_read { block.call }
    rescue StandardError => e
      GitHub.logger.error(
        "#{self.class.name} failed",
        "error.class" => e.class.name,
        "error.message" => e.message,
      )
      GitHub.dogstats.increment("copilot.expired_student_batched_job.errored")
      raise
    end

    # rubocop:disable Sorbet/ForbidTUntyped -- matches BatchedJob base interface
    sig do
      params(
        args: T.untyped,
        timestamp: Time,
        offset_item_id: Integer,
        progress: Integer,
        options: T.untyped,
      ).returns(T::Array[Integer])
    end
    def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
      CouponRedemption
        .expired
        .joins(:coupon)
        .joins("INNER JOIN plan_subscriptions ON plan_subscriptions.user_id = coupon_redemptions.billable_entity_id AND coupon_redemptions.billable_entity_type = 'User'")
        .joins("INNER JOIN subscription_items ON subscription_items.plan_subscription_id = plan_subscriptions.id")
        .where(coupons: { code: Copilot::STUDENT_COUPON_CODES })
        .where("subscription_items.quantity > 0")
        .where("coupon_redemptions.id > ?", offset_item_id)
        .where("coupon_redemptions.id <= ?", offset_item_id + QUERY_LIMIT)
        .order("coupon_redemptions.id ASC")
        .limit(BATCH_SIZE)
        .distinct
        .pluck(:id)
    end

    sig { params(batch: T::Array[Integer], args: T.untyped, options: T.untyped).void }
    def process_batch(batch, *args, **options)
      user_ids = CouponRedemption.where(id: batch).distinct.pluck(:billable_entity_id)
      user_ids.each do |user_id|
        Copilot::SubscriptionItemExpiredCheckJob.perform_later(user_id: user_id, scheduled: true)
      end
    end

    sig { params(batch: T::Array[Integer], options: T.untyped).returns(T::Boolean) }
    def has_next_batch?(batch, **options)
      max_id = CouponRedemption.maximum(:id).to_i
      if batch.size >= BATCH_SIZE
        max_id > T.must(batch.max)
      else
        max_id > T.cast(options[:offset_item_id], Integer) + QUERY_LIMIT
      end
    end

    sig { params(batch: T::Array[Integer], args: T.untyped, options: T.untyped).returns(Integer) }
    def next_batch_offset_item_id(batch, *args, **options)
      if batch.size < BATCH_SIZE
        T.cast(options[:offset_item_id], Integer) + QUERY_LIMIT
      else
        T.must(batch.max)
      end
    end

    sig { params(finished_successfully: T::Boolean, options: T.untyped).void }
    def ensure_perform(finished_successfully:, **options)
      if finished_successfully
        GitHub.logger.info("Completed processing all expired student coupons")
        GitHub.dogstats.increment("copilot.expired_student_batched_job.completed")
      end
    end
    # rubocop:enable Sorbet/ForbidTUntyped
  end
end
