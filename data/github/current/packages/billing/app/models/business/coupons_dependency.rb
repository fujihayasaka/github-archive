# typed: strict
# frozen_string_literal: true

module Business::CouponsDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern
  include Couponable

  requires_ancestor { Business::BillingDependency }

  # Expires the active coupon, if one exists.
  #
  # Currently, enterprise coupons only support dollar discounts, so we don't
  # need to worry about plans changing when an enterprise coupon expires.
  #
  # Returns true if there was an active coupon and it's now expired.
  # Returns false if there's no active coupon.
  sig { params(quiet: T.nilable(T::Boolean)).returns(T::Boolean) }
  def expire_active_coupon(quiet: false)
    T.bind(self, Business)
    # Clear coupon cache to ensure our guard clause is accurate.
    clear_coupon_local_cache

    coupon = self.coupon
    return false if coupon.blank?

    GitHub.dogstats.increment("billing.biz.expire_active_coupon.action", tags: ["live:true", "reason:default", "action:downgrade"])
    BillingNotificationsMailer.business_coupon_expired(self, education_coupon: coupon.education_coupon?).deliver_later unless quiet


    # Should we show a UI notice to the enterprise that their coupon is expiring?
    #   if so, would that be for billing managers only?
    #   (that would be a scope increase)

    clear_coupon_local_cache

    Business.transaction do
      coupon_redemption&.expire!
      # downgrade business to free plan if there
      # is no valid payment method associated with it
      downgrade_to_free_plan unless has_valid_payment_method?
      save!
    end
  end

  # Best used in an after_save. Coupons are cached locally using an ivar,
  # but that can cause problems in tests. For example:
  #
  # 1. Create user w/ coupon
  # 2. Upgrade user in separate codepath
  # 3. Call user.reload on user object from #1
  # 4. user.coupon still exists, even though it shouldn't!
  #
  # Clearing the local cache fixes this issue.
  sig { void }
  def clear_coupon_local_cache
    clear_preloaded_batch_method_value(:coupon)
    clear_preloaded_batch_method_value(:coupon_redemption)
    self.new_coupon_code = nil
  end

  # Does the business currently have an active coupon?
  # coupon_redemption.expires_at can be in the past while it hasn't
  # been marked as expired through the job.
  sig { returns(T::Boolean) }
  def has_an_active_coupon?
    redemption = coupon_redemption
    !redemption.nil? && !redemption.stale?
  end

  # Given a coupon code, attempts to validate it. Any errors will be
  # set on this business's `coupon` attribute.
  #
  # code - A String code or Coupon object to validate against this business.
  # options - The Hash options (default: {}):
  #           :actor - User attempting perform the redemption
  #           :allow_reuse - A Boolean that permits a previously-expired coupon
  #                          to be reused on this business (default: false).
  #           :validate_active_coupon - A Boolean that can be used to control
  #                                     if active coupons are validated (default: true)
  #           :direct_upgrade - A Boolean that enables a coupon applied to a GHEC org
  #                             to be transferred to the EA it's upgrading to (default: false)
  #           :coupon_redemption_expires_at – A time object that
  #                reflects when the coupon discount should expire.
  #                Currently only applicable if direct_upgrade is true (default: nil).
  sig do
    params(
      code: T.any(String, Coupon),
      opts: T::Hash[Symbol, T.untyped]
    ).returns(T.any(Coupon, T::Boolean))
  end
  def validate_coupon(code, opts = {})
    if opts[:validate_active_coupon].nil?
      opts[:validate_active_coupon] = true
    end

    if has_commercial_interaction_restriction?
      errors.add(:coupon, "can't be redeemed - #{trade_screening_status}")
      return false
    end

    # TODO: Business#delegate_billing_to_business? always returns false so this is not needed.
    # Leaving it here in case we want to refactor the same code in User::CouponsDependency
    if delegate_billing_to_business?
      errors.add(:coupon, "can't be redeemed against enterprise account organizations.")
      return false
    end

    coupon = Coupon.find_by_code(code)

    if coupon.blank?
      errors.add(:coupon, "can't be found.")
      return false
    end

    if has_an_active_coupon? && opts[:validate_active_coupon]
      errors.add(:coupon, "can't be redeemed - you have an active coupon!")
      return false
    end

    if billing_type != "card"
      errors.add(:coupon, "can't be redeemed with your account. Please contact support.")
      return false
    end

    unless opts[:actor]
      errors.add(:coupon, "requires an actor for redeeming.")
      return false
    end

    if !coupon.redeemable_by?(opts[:actor]) && !opts[:direct_upgrade]
      errors.add(:coupon, "can't be redeemed with your account. Please contact support.")
      return false
    end

    if coupon.expires_at < Time.now && !opts[:direct_upgrade]
      errors.add(:coupon, "has expired. Sorry!")
      return false
    end

    if coupon.limit == 0
      errors.add(:coupon, "can't be redeemed any more times.")
      return false
    end

    if coupon_plan = coupon.plan
      if plan.coupon? && coupon.plan != plan
        errors.add(:coupon, "can't be used with the #{plan} plan.")
        return false
      end
    end

    if !opts[:allow_reuse] && expired_coupons.map(&:coupon_id).include?(coupon.id)
      errors.add(:coupon, "has already been redeemed.")
      return false
    end

    coupon
  end

  # Redeems a coupon and applies the discount to this business. If the coupon
  # is a "trial" for a paid plan, upgrades the business's plan automatically
  # and sets the billed_on appropriately.
  #
  # Only one coupon may be redeemed at a time. If an active coupon exists,
  # this method will fail to redeem the new coupon.
  #
  # code  - A coupon code String or the Coupon object to be
  #         redeemed.
  # options - The Hash options (default: {}):
  #           :actor       - The User who is redeeming this coupon (default: self).
  #           :allow_reuse - A Boolean that permits a previously-expired coupon
  #                          to be reused on this user (default: false).
  #           :instrument  - Tracks the change to the business's plan (default: true).
  #           :direct_upgrade - A Boolean that enables a coupon applied to a GHEC org
  #                             to be transferred to the EA it's upgrading to (default: false)
  #           :coupon_redemption_expires_at – A time object that
  #                reflects when the coupon discount should expire.
  #                Currently only applicable if direct_upgrade is true (default: nil).
  sig do
    params(code: T.any(String, Coupon), opts: T::Hash[Symbol, T.untyped])
      .returns(T.any(CouponRedemption, T.nilable(T::Boolean)))
  end
  def redeem_coupon(code, opts = {})
    T.bind(self, Business)

    return false if spammy? || metered_plan?

    opts = opts.reverse_merge \
      allow_reuse: false,
      instrument: true

    return false unless coupon = validate_coupon(code, opts)
    coupon = T.cast(coupon, Coupon)

    actor = opts.fetch(:actor)

    clear_coupon_local_cache

    redeemed = transaction do
      expire_active_coupon if coupon_redemption
      redemption = coupon_redemptions.create(coupon: coupon)
      clear_coupon_local_cache
      if opts[:coupon_redemption_expires_at].present?
        redemption.update!(expires_at: opts[:coupon_redemption_expires_at])
      end

      # Reset billing_attempts if coupon fully covers the cost
      new_billing_attempts = trial? ? 0 : billing_attempts

      # Figure out when to bill them next
      start_date = billed_on || GitHub::Billing.today

      # Create or attach a Customer record for this user
      # This is needed since we set the `billed_on` date here
      create_customer_service = ::Billing::CreateCustomer.perform(self, actor: actor)
      unless create_customer_service.success?
        GitHub.dogstats.increment("billing.redeem_coupon.create_customer", tags: ["success:false", "cause:service"])
        errors.add(:coupon, "cannot be redeemed. Unable to create a customer for this account.")
        raise ActiveRecord::Rollback
      end
      customer = create_customer_service.customer
      unless customer.update(bill_cycle_day: start_date.day)
        GitHub.dogstats.increment("billing.redeem_coupon.create_customer", tags: ["success:false", "cause:bill_cycle_day"])
        errors.add(:coupon, "cannot be redeemed. Unable to create a customer for this account.")
        raise ActiveRecord::Rollback
      end

      if trial?
        convert_trial(actor, staff_initiated: actor.has_staff_role?)
        self.seats = [1, total_consumed_licenses].max
      end

      # This performs the upgrade to business_plus if it's not already on business plus
      enable!
      # TODO: do seats need to be changed or should they remain the same?
      # TODO: what should we assign as the next billing date here?
      update_billing_date(next_billing_date: start_date, billing_attempts: new_billing_attempts)

      if coupon.non_profit?
        result = T.must(handle_non_profit_coupon)

        unless result.success?
          errors.add(:coupon, "cannot be redeemed. #{result.message}")
          raise ActiveRecord::Rollback
        end
      end

      redemption
    end

    if redeemed
      GlobalInstrumenter.instrument(
        "billing.redeem_coupon",
        actor_id: opts[:actor]&.id,
        business_id: id,
        coupon_id: coupon.id,
      )
    end

    redeemed
  end

  # Handle refunds for non-profit coupons
  sig { returns(T.nilable(GitHub::Billing::Result)) }
  def handle_non_profit_coupon
    return unless T.must(coupon).non_profit?

    refund_result = GitHub::Billing::Result.success
    last_transaction = billing_transactions.sales.last
    if last_transaction.try(:is_within_a_year_ago?) && last_transaction.try(:refundable?)
      refund_result = GitHub::Billing.refund_transaction(last_transaction.transaction_id)
    end
    refund_result
  end

  sig do
    params(
          org_coupon_redemption: CouponRedemption
        )
      .returns(T.any(CouponRedemption, T.nilable(T::Boolean)))
  end
  def apply_coupon_from_upgrading_org(org_coupon_redemption:)
    return false unless coupon = org_coupon_redemption.coupon
    return false if org_coupon_redemption.expires_at < GitHub::Billing.now

    coupon.increment!(:limit)

    # coupon_redemption_expires_at reflects when the discount from the
    # GHEC org's transferred coupon should expire for the EA.
    redemption = self.redeem_coupon(
      coupon.code,
      actor: User.ghost,
      direct_upgrade: true,
      coupon_redemption_expires_at: org_coupon_redemption.expires_at
    )
    redemption
  end

  mixes_in_class_methods Couponable::ClassMethods
end
