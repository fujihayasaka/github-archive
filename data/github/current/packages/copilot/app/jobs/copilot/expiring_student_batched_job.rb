# typed: strict
# frozen_string_literal: true

module Copilot
  # BatchedJob that finds users whose student coupons expire within
  # EXPIRATION_WARNING_DURATION and sends them an expiration warning email.
  #
  # All JOINs stay within the billing cluster (coupon_redemptions, coupons,
  # plan_subscriptions, subscription_items). User records are loaded
  # separately after plucking IDs.
  class ExpiringStudentBatchedJob < BatchedJob
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
      GitHub.dogstats.increment("copilot.expiring_student_batched_job.errored")
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
        .joins(:coupon)
        .joins("INNER JOIN plan_subscriptions ON plan_subscriptions.user_id = coupon_redemptions.billable_entity_id AND coupon_redemptions.billable_entity_type = 'User'")
        .joins("INNER JOIN subscription_items ON subscription_items.plan_subscription_id = plan_subscriptions.id")
        .where(coupons: { code: Copilot::STUDENT_COUPON_CODES })
        .where(coupon_redemptions: { expires_at: (timestamp + Copilot::FreeUser::EXPIRATION_WARNING_DURATION).all_day })
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
      ::User.where(id: user_ids).find_each do |user|
        Copilot::StudentExpirationHelper.send_expiration_warning(user)
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
        GitHub.logger.info("Completed processing all expiring student coupons")
        GitHub.dogstats.increment("copilot.expiring_student_batched_job.completed")
      end
    end
    # rubocop:enable Sorbet/ForbidTUntyped
  end
end
