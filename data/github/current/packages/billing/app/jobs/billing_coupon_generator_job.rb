# typed: strict
# frozen_string_literal: true

# Background job that generates multiple coupons with a limit of 1.
#
# - For each coupon, a unique code is generated,
#     optionally prefixed by prefix
# - Default attributes can be overridden except for
#     :code which is generated and :limit which is always 1
# - Job retries on configured RETRYABLE_ERRORS.
class BillingCouponGeneratorJob < BillingJob
  include GitHub::Memoizer

  BATCH_LIMIT = 1000 # don't let this job go hog wild
  KEYS = [:discount, :duration, :expires_at, :group, :note, :staff_actor_only].freeze

  class GenerationError < StandardError; end

  # We need write access to the Users cluster (where coupons live)
  # and to the Billing cluster (where coupon_batches live)
  use_primaries ApplicationRecord::Mysql1, ApplicationRecord::Billing

  retry_on_dirty_exit
  RETRYABLE_ERRORS = T.let([
    ActiveRecord::RecordNotUnique,
    BillingCouponGeneratorJob::GenerationError,
  ].freeze, T::Array[T.class_of(StandardError)])

  RETRYABLE_ERRORS.each do |retriable_error|
    retry_on retriable_error, attempts: 3 do |job, error|
      GitHub.logger.error({
        message: "Failed to retry generate coupons job",
        exception: error,
        "code.namespace": self.class.name,
        "gh.coupon.job_arguments": job.arguments,
      })
      Failbot.report(error)
      job.coupon_batch.failed!
    end
  end

  sig { returns(T.nilable(CouponBatch)) }
  attr_reader :coupon_batch

  sig { params(coupon_batch: CouponBatch).void }
  def perform(coupon_batch)
    @coupon_batch = T.let(coupon_batch, T.nilable(CouponBatch))
    count = coupon_batch.quantity - coupon_batch.coupons.count
    message = "Started generating #{count} coupons"
    message += " with prefix #{coupon_batch.prefix}" if coupon_batch.prefix
    GitHub.logger.info(message)

    validation_coupon = Coupon.new(coupon_batch.coupon_params)
    if count > BATCH_LIMIT
      GitHub.logger.error("Unable to generate coupons: Count must be less than #{BATCH_LIMIT}")
    elsif count < 1
      GitHub.logger.error("Unable to generate coupons: Count must be greater than 0")
    elsif !validation_coupon.valid?
      GitHub.logger.error("Unable to generate coupons: #{validation_coupon.errors.full_messages.join(", ")}")
    else
      created_coupons = 0
      count.times do
        result = Billing.domain.coupons.create(
          code: coupon_batch.generate_unique_code,
          coupon_discount_amount: validation_coupon.discount,
          coupon_group: validation_coupon.group,
          coupon_expires_at: validation_coupon.expires_at,
          coupon_note: validation_coupon.note,
          coupon_product_target: coupon_batch.product_target,
          coupon_batch: coupon_batch,
          actor: coupon_batch.actor || User.staff_user,
          redemption_limit: validation_coupon.limit.to_i,
          redemption_duration_in_days: validation_coupon.duration.to_i,
          applicable_by_staff_only: validation_coupon.staff_actor_only
        )

        if result.is_a?(GH::Result::Ok)
          GitHub.logger.info("Created coupon with code: #{result.value.code}")
          GitHub.dogstats.increment("billing.coupon.generate.success")
          created_coupons += 1
        elsif result.is_a?(GH::Result::Error)
          GitHub.logger.info("Failed to generate coupon: #{result.message}")
          GitHub.dogstats.increment("billing.coupon.generate.failure")
          with_write { coupon_batch.update!(status: :retrying, status_message: result.message) }
          raise GenerationError.new "Failed to generate coupon!" # raise error to trigger retry
        end
      end

      GitHub.logger.info("Created #{created_coupons} coupons")
      with_write { coupon_batch.success! }
    end
  end
end
