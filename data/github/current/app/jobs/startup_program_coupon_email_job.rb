# typed: strict
# frozen_string_literal: true

class StartupProgramCouponEmailJob < BatchedJob
  queue_as :startup_program_renewal_email
  schedule interval: 1.day, condition: -> { GitHub.billing_enabled? }

  retry_on_dirty_exit

  # This method accepts a batch of CouponRedemptions and processes them by iterating
  # over each billable_entity (Organization or Business), then matches the following criteria and sends them an email:
  # - coupon is not expired
  # - has a GFS coupon that will expire in 30 days or 14 days or 5 days
  # - has not already received an email
  #
  # @param batch [ActiveRecord::Relation] A batch of CouponRedemption
  # @param args [Array] Arguments passed to the job
  # @param options [Hash] Options passed to the job
  #
  # @return [ActiveRecord::Relation] The next batch of CouponRedemption
  sig { params(batch: ActiveRecord::Relation, args: T.untyped, options: T.untyped).returns(T.untyped) }
  def process_batch(batch, *args, **options)
    batch.each do |coupon_redemption|
      next if coupon_redemption.expired?

      entity = coupon_redemption.billable_entity
      next unless entity
      next if already_sent?(entity)

      enqueue_email(entity)
    end
  end

  private

  sig { params(args: T.untyped, timestamp: Time, offset_item_id: Integer, progress: Integer, options: T.untyped).returns(ActiveRecord::Relation) }
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    startups_coupon_redemptions.where(expires_at: in_thirty_days.all_day)
    .or(startups_coupon_redemptions.where(expires_at: in_fourteen_days.all_day))
    .or(startups_coupon_redemptions.where(expires_at: in_five_days.all_day))
  end

  sig { returns(ActiveRecord::Relation) }
  def startups_coupon_redemptions
    CouponRedemption
      .joins(:coupon)
      .where(
        "coupons.code in ('GFSYR1', 'GFSPartnerYR1', 'GFSYR2', 'GFSPartnerYR2', 'MSYR2') " \
        "OR coupons.code LIKE 'gfs-%'" \
        "OR coupons.code LIKE 'gfspartner-%'"
      )
  end

  sig { params(entity: T.any(Organization, Business)).returns(T::Boolean) }
  def already_sent?(entity)
    !!Growth::LastActivity::KV.store.get(startup_coupon_entity_key(entity)).value { false }
  end

  sig { params(entity: T.any(Organization, Business)).returns(String) }
  def startup_coupon_entity_key(entity)
    expiration_days = (entity.coupon_redemption.expires_at.in_time_zone.to_date - GitHub::Billing.today).to_i
    "startup_coupon_email_sent:#{entity.class.name}.#{entity.id}.#{expiration_days}"
  end

  sig { params(entity: T.any(Organization, Business)).void }
  def enqueue_email(entity)
    StartupProgramMailer.coupon_expiration(entity).deliver_later
    email_sent!(entity)
  end

  sig { params(entity: T.any(Organization, Business)).void }
  def email_sent!(entity)
    expiration_days = (entity.coupon_redemption.expires_at.in_time_zone.to_date - GitHub::Billing.today).to_i
    expire_in = entity.coupon_redemption.expires_at.in_time_zone.to_date

    with_write do
      Growth::LastActivity::KV.store.set(
        startup_coupon_entity_key(entity),
        Time.current.iso8601,
        expires: expire_in
      )
    end
  end

  sig { returns(Date) }
  def today
    GitHub::Billing.today.to_date
  end

  sig { returns(Date) }
  def in_thirty_days
    (today + 30.days).to_date
  end

  sig { returns(Date) }
  def in_fourteen_days
    (today + 14.days).to_date
  end

  sig { returns(Date) }
  def in_five_days
    (today + 5.days).to_date
  end
end
