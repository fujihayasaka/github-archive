# typed: strict
# frozen_string_literal: true

# When a billable entity redeems a coupon (i.e., applies it to their account)
# we create a CouponRedeption to track which billable entity redeemed it, how
# long the coupon is active, and to update the Coupon record's usage
# counter (if it's usage count bound).
class CouponRedemption < ApplicationRecord::Domain::Users

  self.ignored_columns = %w[user_id]

  belongs_to :coupon

  belongs_to :billable_entity, polymorphic: true

  before_create :set_expiration
  after_create  :decrease_coupon_limit,
                :track_coupon_redemption
  after_commit :synchronize_plan_subscription, on: :create

  scope :expired, -> { where(expired: true) }
  scope :active,  -> { where(expired: false) }
  scope :for_coupon, ->(coupon_or_id) { where(coupon_id: coupon_or_id) }
  scope :for_user, ->(user_or_id) { where(billable_entity_id: user_or_id, billable_entity_type: "User") }
  scope :for_billable_entity, ->(billable_entity) { where(billable_entity: billable_entity) }
  scope :of_billable_entity_type, ->(entity_classname) { where(billable_entity_type: entity_classname) }

  # Collects all coupon redemptions expiring within a specified date range.
  scope :expiring_within_range, -> (start_at:, end_at:) {
    where("expires_at >= ? AND expires_at < ?",
      start_at, end_at
    ).active
  }

  # Collects all coupon redemptions that are expiring two weeks from today.
  scope :expiring_in_two_weeks, -> (from: GitHub::Billing.now.at_midnight) {
    expiring_within_range(start_at: from + 14.days, end_at: from + 15.days)
  }

  # Collects all coupon redemptions that are expiring one week from today.
  scope :expiring_in_one_week, -> (from: GitHub::Billing.now.at_midnight) {
    expiring_within_range(start_at: from + 7.days, end_at: from + 8.days)
  }

  scope :expiring_now, lambda {
    includes(:billable_entity)
      .where(
        "expires_at < ? AND expired = ?", GitHub::Billing.now, false
      )
  }

  scope :expiring_before, lambda { |expiration_time|
    where("expires_at < ? AND expired = ?", expiration_time, false)
  }

  # Public: Expire coupons that became stale after the previous billing cycle.
  #
  sig { void }
  def self.expire!
    should_be_expired_and_billable_entity_has_been_billed.each do |coupon_redemption|
      begin
        if billable_entity = coupon_redemption.billable_entity
          billable_entity.expire_active_coupon
        else
          coupon_redemption.expire!
        end
      rescue StandardError => e # rubocop:todo Lint/GenericRescue
        # We don't want to raise an exception if the coupon redemption raises an exception
        # because we don't want to stop the rest of the coupon redemptions from expiring
        # and we also don't want the bill run to stop (i.e. BillingRunStartJob)
        Failbot.report(e)
        GitHub.dogstats.increment("coupon_redemption.expirebang.errors", tags: ["error:#{e.class}"])
      end
    end
  end

  # Public: All coupons that are safe to expire
  #
  # We need make sure that the billable_entity's billing date has been
  # advanced past the expiration date of their coupon
  # before we can safely expire that coupon
  # because sometimes the billing system
  # might lag behind real calendar time
  sig { returns(T::Array[CouponRedemption]) }
  def self.should_be_expired_and_billable_entity_has_been_billed
    expiring_before(GitHub::Billing.now.beginning_of_day)
      .select(&:expires_before_billing_date?)
  end

  # Expires an active coupon redemption by setting its `expired`
  # attribute to true. Also changes the expires_at timestamp, if
  # we must. Doesn't save or anything.
  #
  sig { void }
  def expire
    self.expires_at = GitHub::Billing.now.in_time_zone if expires_at > GitHub::Billing.now
    self.expired = true
  end

  # Runs `expire` but also saves the record.
  # Triggers instrumentation
  #
  # skip_sync - When true, skips the external subscription synchronization
  #            (default: false)
  sig { params(skip_sync: T::Boolean).returns(T::Boolean) }
  def expire!(skip_sync: false)
    GitHub.dogstats.increment("coupon.expired")
    expire
    if save!
      synchronize_plan_subscription unless skip_sync
      GitHub.instrument("coupon_redemption.expire", {
        id: self.id,
        billable_entity_type: billable_entity_type,
        billable_entity_id: billable_entity_id,
        coupon_id: self.coupon_id,
      })
      true
    else
      false
    end
  end

  sig { returns(T::Boolean) }
  def expires_this_billing_cycle?
    if billed_on = billable_entity&.billed_on
      self.expires_at.to_date.before?(billed_on)
    else
      false
    end
  end

  # Public: Checks to see if the coupon redemption expired
  # since the last time the account got billed
  sig { returns(T::Boolean) }
  def expired_since_last_billing?
    if previous_billing_date = billable_entity&.previous_billing_date
      self.expires_at.to_date.after?(previous_billing_date)
    else
      false
    end
  end

  # Public: Checks to see if the coupon redemption will expire before
  # the billable entity's next billing date
  #
  sig { returns(T::Boolean) }
  def expires_before_billing_date?
    billing_date = billable_entity&.billed_on || GitHub::Billing.today
    self.expires_at.to_date < billing_date
  end

  # Check to see if this redemption is past its expiration date
  #
  sig { returns(T::Boolean) }
  def stale?
    self.expires_at < GitHub::Billing.now.beginning_of_day
  end

  sig { returns(ActiveSupport::TimeWithZone) }
  def expires_at
    self[:expires_at].in_billing_timezone
  end

  private

  sig { void }
  def synchronize_plan_subscription
    GitHub.dogstats.increment("billing.coupon_redemption.synchronize_plan_subscription", tags: [
      "has_external_subscription:#{!!billable_entity&.external_subscription?}",
      "has_payment_method:#{!!billable_entity&.has_valid_payment_method?(feature_type: :noncommercial)}"
    ])
    billable_entity&.create_or_update_external_subscription_once!(force: true)
  end

  sig { void }
  def set_expiration
    self[:expires_at] ||= GitHub::Billing.now + T.must(coupon).duration.days
  end

  sig { void }
  def decrease_coupon_limit
    coupon = self.coupon
    return if coupon.nil?

    coupon.decrement!(:limit)
  end

  sig { void }
  def track_coupon_redemption
    coupon = self.coupon
    return if coupon.nil?

    if (coupon.limit + coupon.coupon_redemptions.count) >= 25
      GitHub.dogstats.increment("coupon.redeemed", tags: [
        "group:#{coupon.group.present? ? coupon.group : 'no_group'}",
        "code:#{coupon.code}",
      ])
    else
      GitHub.dogstats.increment("coupon.redeemed", tags: [
        "group:#{coupon.group.present? ? coupon.group : 'no_group'}",
      ])
    end
  end
end
