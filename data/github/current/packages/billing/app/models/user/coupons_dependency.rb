# typed: strict
# frozen_string_literal: true

module User::CouponsDependency
  extend T::Sig
  extend T::Helpers
  extend ActiveSupport::Concern

  include Couponable

  requires_ancestor { User::BillingDependency }

  included do
    T.bind(self, T.class_of(User))

    validate     :coupon_required?, :validate_coupon!
    after_save   :redeem_coupon!, :clear_coupon_local_cache
    after_update :end_trial_on_plan_change

    after_commit :set_expired_education_coupon_notice, on: [:create, :update]
  end

  # A coupon code can be set for easy redemption.
  #
  # @user.coupon = "my-code"
  # @user.save
  sig { params(coupon_or_code: T.nilable(T.any(Coupon, String))).void }
  def coupon=(coupon_or_code)
    return if coupon_or_code.blank?
    clear_coupon_local_cache
    self.new_coupon_code = if coupon_or_code.is_a?(Coupon)
      coupon_or_code.code
    else
      coupon_or_code
    end
  end

  # Was this user using a coupon that expired in a previous billing
  # cycle?
  #
  sig { returns(T::Boolean) }
  def coupon_expired_since_last_billing?
    !!last_expired_coupon_redemption&.expired_since_last_billing?
  end

  # Is this user's most recently expired coupon an educational coupon?
  # We expose this because we need to communicate slightly differently to
  # users that were on educational coupons since they may not know that
  # they were actually using a coupon.
  sig { returns(T::Boolean) }
  def expired_education_coupon?
    !!last_expired_coupon_redemption&.coupon&.education_coupon?
  end

  sig { returns(T.nilable(T::Boolean)) }
  def has_expired_education_coupon?
    # TODO: this is nilable because either plan.free? or payment_amount.zero? may return nil...
    # We can fix that would but require extra work on ensuring plan.free? doesn't blow up
    # and payment_amount always returns a value + adding type checks there
    disabled? && !plan.free? && !payment_amount.zero? && expired_education_coupon?
  end

  sig { void }
  def set_expired_education_coupon_notice
    return unless has_expired_education_coupon?

    Billing::ExpiredEducationCouponCheckJob.perform_later(self)
  end

  # Does the user currently have an active coupon?
  # coupon_redemption.expires_at can be in the past while it hasn't
  # been marked as expired through the job.
  sig { returns(T::Boolean) }
  def has_an_active_coupon?
    redemption = coupon_redemption
    !redemption.nil? && !redemption.stale?
  end

  # Does the user currently have an active plan-specific coupon?
  sig { returns(T::Boolean) }
  def has_a_plan_specific_coupon?
    redemption = coupon_redemption
    coupon = self.coupon

    !!(redemption.present? && !redemption.stale? && coupon.present? && coupon.plan_specific?)
  end

  # Is this user currently enjoying a free trial?
  sig { returns(T::Boolean) }
  def free_trial?
    if has_an_active_coupon?
      coupon = T.must(self.coupon)
      (coupon.trial? && data_packs == 0) ||
        coupon.discount.to_f >= plan.cost + data_pack_price.to_f
    else
      false
    end
  end

  # Does this free trial only work for a specific plan?
  sig { returns(T::Boolean) }
  def free_trial_locked_to_plan?
    coupon = self.coupon

    free_trial? && !coupon.nil? && coupon.plan_specific?
  end

  # User is on a free trial that hasn't expired yet, but
  # they're changing plans and entering their cc# info.
  #
  # In other words, they're upgrading out of their free trial.
  sig { returns(T::Boolean) }
  def upgrading_out_of_free_trial?
    return false if leaving_free_plan?
    old_plan = GitHub::Plan.find(plan_before_last_save)
    saved_change_to_plan? && old_plan.present? && free_trial_locked_to_plan? && plan.cost > old_plan.cost
  end

  # User is on a free trial that hasn't expired yet, but
  # they're downgrading plans.
  #
  # In other words, they're dowgrading out of their free trial.
  sig { returns(T::Boolean) }
  def downgrading_out_of_free_trial?
    return false if leaving_free_plan?
    old_plan = GitHub::Plan.find(plan_before_last_save)
    saved_change_to_plan? && old_plan.present? && free_trial_locked_to_plan? && plan.cost < old_plan.cost
  end

  # Lets you know how many days are remaining in this user's free trial,
  # if it is a trial. See Coupon#trial? for more info on trials.
  sig { returns(T.nilable(Integer)) }
  def trial_days_left
    (T.must(coupon_redemption).expires_at.to_date - Date.today).to_i if free_trial?
  end

  # The monthly discount in dollars this user should receive due to any active
  # coupons.
  sig do
    params(
      based_on_plan: T.nilable(GitHub::Plan),
      based_on_seats: T.nilable(Integer),
      based_on_data_packs: T.nilable(Integer)
    ).returns(Billing::Money)
  end
  def discount(based_on_plan: plan, based_on_seats: seats, based_on_data_packs: data_packs)
    Billing::Pricing.new(
      account: T.cast(self, User),
      plan: based_on_plan,
      seats: based_on_seats,
      data_packs: based_on_data_packs,
      plan_duration: User::BillingDependency::MONTHLY_PLAN,
    ).discount
  end

  # Amount of unused discount available to put toward add-ons like data packs,
  # after discount has been applied to plans and already-purchased add-ons.
  sig { returns(Billing::Money) }
  def remaining_discount
    coupon = self.coupon
    return Billing::Money.new(0) if coupon.blank? || coupon.percentage? || coupon.plan_specific?

    plan_list_price = Billing::Pricing.new(
      account: T.cast(self, User),
      plan_duration: User::BillingDependency::MONTHLY_PLAN,
    ).undiscounted

    remaining = Billing::Money.new(coupon.discount.to_f * 100) - plan_list_price
    [remaining, Billing::Money.new(0)].max
  end

  # Some plans require a coupon. Maybe they are too awesome for normal
  # use, who knows.
  #
  # If this method returns `true` it will also set
  # `errors[:coupon]` to an error message if no coupon is set.
  #
  sig { returns(T::Boolean) }
  def coupon_required?
    return false if has_staff_role?

    if plan && plan.coupon? && coupon.blank?
      errors.add(:coupon, "is required for the #{plan.display_name} plan.")
      true
    else
      false
    end
  end

  # Given a coupon code, attempts to validate it. Any errors will be
  # set on this user's `coupon` attribute.
  #
  # code - A String code or Coupon object to validate against this user.
  # options - The Hash options (default: {}):
  #           :actor - User attempting perform the redemption
  #           :allow_reuse - A Boolean that permits a previously-expired coupon
  #                          to be reused on this user (default: false).
  #           :validate_active_coupon - A Boolean that can be used to control
  #                                     if active coupons are validated (default: true)
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

    if has_any_trade_restrictions?
      errors.add(:coupon, "can't be redeemed - #{TradeControls::Notices.notice_as_plaintext(:user_account_restricted)}")
      return false
    end

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
      errors.add(:coupon,
        "can't be redeemed with your account. Please contact support.")
      return false
    end

    unless coupon.redeemable_by?(opts[:actor])
      errors.add(:coupon,
        "can't be redeemed with your account. Please contact support.")
      return false
    end

    if coupon.expires_at < Time.now
      errors.add(:coupon, "has expired. Sorry!")
      return false
    end

    if coupon.limit == 0
      errors.add(:coupon, "can't be redeemed any more times.")
      return false
    end

    if coupon_plan = coupon.plan
      if !coupon_plan.free? && coupon_plan.orgs? && !organization?
        errors.add(:coupon, "is for organizations only.")
        return false
      end

      if !coupon_plan.free? && !coupon_plan.orgs? && organization?
        errors.add(:coupon, "is for users only.")
        return false
      end

      if plan.coupon? && coupon_plan != plan
        errors.add(:coupon, "can't be used with the #{plan.display_name} plan.")
        return false
      end

      plan_change_is_upgrade = coupon_plan > plan
      coupon_plan_change_is_valid = can_change_plan_to?(coupon_plan, actor: opts[:actor] || self)
      plan_change_is_invalid = !(coupon_plan_change_is_valid && plan_change_is_upgrade)
      if coupon_plan != plan && !coupon.trial? && plan_change_is_invalid
        errors.add(:coupon, "can't be used with the #{plan.display_name} plan.")
        return false
      end

      if private_repo_count_for_limit_check > coupon_plan.repos
        errors.add(:coupon, "can't be used with #{private_repo_count_for_limit_check} private repositories.")
        return false
      end

    end

    if !opts[:allow_reuse] && expired_coupons.map(&:coupon_id).include?(coupon.id)
      errors.add(:coupon, "has already been redeemed.")
      return false
    end

    coupon
  end

  # Same as `validate_coupon` but uses a coupon set with this user's
  # `coupon=` accessor.
  sig { returns(T.nilable(T.any(Coupon, T::Boolean))) }
  def validate_coupon!
    code = new_coupon_code
    validate_coupon(code) if code.present?
  end

  # Redeems a coupon and applies the discount to this user. If the coupon
  # is a "trial" for a paid plan, upgrades the user's plan automatically
  # and sets the billed_on appropriately.
  #
  # So if the user is on Free and there's a trial coupon for Small,
  # we'll switch the user to Small without asking for their cc# info.
  #
  # This will also upgrade the user's plan if their coupon affords them
  # a large plan. Say, a $12 discount applied to a Free plan. Bumps you
  # up to Small.
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
  #           :instrument  - Tracks the change to the user's plan (default: true).
  sig do
    params(code: T.any(String, Coupon), opts: T::Hash[Symbol, T.untyped])
      .returns(T.any(CouponRedemption, T.nilable(T::Boolean)))
  end
  def redeem_coupon(code, opts = {})
    T.bind(self, User)

    return false if spammy?

    opts = opts.reverse_merge \
      actor: self,
      allow_reuse: false,
      instrument: true

    return false unless coupon = validate_coupon(code, opts)
    coupon = T.cast(coupon, Coupon)

    clear_coupon_local_cache

    redeemed = transaction do
      expire_active_coupon if coupon_redemption
      redemption = coupon_redemptions.create(coupon: coupon)
      clear_coupon_local_cache

      old_plan = plan
      plan = best_plan_for_coupon

      # Reset billing_attempts if coupon fully covers the cost
      new_billing_attempts = free_trial? ? 0 : billing_attempts

      # Figure out when to bill them next
      start_date = billed_on || GitHub::Billing.today

      # Create or attach a Customer record for this user
      # This is needed since we set the `billed_on` date here
      create_customer_service = ::Billing::CreateCustomer.perform(self, actor: opts[:actor])
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

      if coupon.plan&.business_plus? && on_enterprise_cloud_trial?
        enterprise_cloud_trial.deactivate!
        self.seats = filled_seats
      end

      # Bump them if we need a new_plan.
      if old_plan != plan
        update \
          plan: plan,
          billed_on: start_date,
          billing_attempts: new_billing_attempts,
          seats: plan.per_seat? ? default_seats(new_plan: plan) : 0,
          disabled: false

        if opts[:instrument]
          track_plan_change(opts[:actor], old_plan, coupon: coupon)
        end
      else
        update \
          billed_on: start_date,
          billing_attempts: new_billing_attempts,
          seats: plan.per_seat? ? default_seats : 0,
          disabled: false
      end

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
        user_id: id,
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

  # Internal: Determine the best plan for the user's current coupon
  #
  sig { returns(GitHub::Plan) }
  def best_plan_for_coupon
    coupon = self.coupon
    return plan if coupon.nil?
    return plan if !coupon.plan_specific? && (plan.per_seat? || plan.pro?)
    return T.must(coupon.plan) if coupon.plan_specific?

    new_plan = if user?
      GitHub::Plan.pro
    elsif organization? && (plan.free? || plan.free_with_addons?)
      # Test for plan.free? is to prevent grandfathered orgs
      # from getting moved to business
      GitHub::Plan.business
    end

    new_plan ||= if organization?
      GitHub::Plan.org_plan_for_discount(discount_after_data_packs)
    else
      GitHub::Plan.user_plan_for_discount(discount_after_data_packs)
    end

    # Don't upgrade user out of coupon discount if currently not paying
    return plan if (payment_amount == 0 && payment_amount(plan: new_plan) > 0) && !will_be_expired?

    # Don't downgrade organizations (users should never be on bigger plans than pro)
    return plan if payment_amount > payment_amount(plan: new_plan) && organization?
    return plan if new_plan.free? && plan.free_with_addons?

    new_plan
  end

  # Same as `redeem_coupon` but uses a coupon set with this user's
  # `coupon=` accessor.
  sig { void }
  def redeem_coupon!
    code = self.new_coupon_code
    redeem_coupon(code) if code.present?
  end

  # Did they just upgrade or downgrade out of a free trial? If so that's awesome,
  # but it means we need to expire their coupon.
  #
  # Should be used as an after_save callback.
  sig { void }
  def end_trial_on_plan_change
    if upgrading_out_of_free_trial? || downgrading_out_of_free_trial?
      expire_active_coupon
    end
  end

  # Expires the active coupon, if one exists.
  #
  # If the user was on a free trial and has private repos,
  # we'll disable them and send an email. If they're on a free
  # trial but don't have any private repos, we'll downgrade them to
  # the 'free' plan.
  #
  # quiet - Boolean to suppress email notifications
  #
  # Returns true if there was an active coupon and it's now expired.
  # Returns false if there's no active coupon.
  sig { params(quiet: T.nilable(T::Boolean)).returns(T.nilable(T::Boolean)) }
  def expire_active_coupon(quiet: false)
    T.bind(self, User)
    # Clear coupon cache to ensure our guard clause is accurate.
    clear_coupon_local_cache
    coupon = self.coupon
    return false if coupon.blank?

    # If the organization is enterprise owned, send an email to clarify why the coupon is being expired
    if organization_enterprise_owned?
      BillingNotificationsMailer.coupon_removed_from_enterprise_owned_organization(self, self.business).deliver_later unless quiet
    elsif !(has_valid_payment_method? || invoiced?)
      # If they're on a free trial, downgrade them to free and check to see if
      # we need to disable their account.
      if plan.legacy?
        disable!
        GitHub.dogstats.increment("billing.expire_active_coupon.action", tags: ["live:true", "reason:legacy", "action:disable"])
      else
        old_plan = plan
        self.plan = "free"
        track_plan_change(self, old_plan)
        GitHub.dogstats.increment("billing.expire_active_coupon.action", tags: ["live:true", "reason:default", "action:downgrade"])
      end
      BillingNotificationsMailer.coupon_expired_failure(self, education_coupon: coupon.education_coupon?).deliver_later unless quiet
    end

    # Delete any notice about coupon expiration when the coupon goes away.
    delete_notice :coupon_will_expire

    clear_coupon_local_cache

    User.transaction do
      coupon_redemption&.expire!
      self.skip_admins_presence_validation = true
      save!
    end
  end

  # Expires the active coupon, if it's stale.
  #
  # Returns true if coupon is stale and gets expired, false otherwise
  sig { returns(T::Boolean) }
  def expire_stale_coupon
    has_stale_coupon_redemptions? && !!expire_active_coupon
  end

  sig { returns(T::Boolean) }
  def has_stale_coupon_redemptions?
    coupon_redemptions.any?(&:stale?)
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

  # Check if the active coupon will already be expired on the
  # next_billing_date.
  #
  # Yearly payments do not take coupon expiration into account currently.
  sig { params(service_started_on: T.nilable(Date)).returns(T::Boolean) }
  def will_be_expired?(service_started_on = nil)
    coupon_redemption = self.coupon_redemption
    !!coupon_redemption &&
      coupon_redemption.expires_at.to_date < (service_started_on || T.must(next_billing_date)).to_date &&
      monthly_plan?
  end

  private

  # Internal: Amount of discount remaining after applying discount ONLY to data packs.
  #
  sig { returns(Float) }
  def discount_after_data_packs
    [discount.to_f - data_pack_monthly_price.to_f, 0.0].max
  end

  # Check whether the plan the user was on is the free plan.
  #
  sig { returns(T::Boolean) }
  def leaving_free_plan?
    saved_change_to_plan? &&
      (plan_before_last_save == "free" || plan == coupon.try(:plan))
  end

  # Finds most recently expired CouponRedemption
  #
  # Returns CouponRedemption or nil
  sig { returns(T.nilable(CouponRedemption)) }
  def last_expired_coupon_redemption
    expired_coupons.order("expires_at ASC").last
  end

  # Private: Expires the users coupon if they're upgrading to business plus
  #
  sig { void }
  def remove_coupon_on_business_plus_upgrade
    return if coupon&.plan&.business_plus?

    if saved_change_to_plan? && has_an_active_coupon? && plan.business_plus?
      T.must(coupon_redemption).expire!(skip_sync: !!skip_update_external_subscription)
    end
  end

  # Private: Check if the target is an organization that is owned by a business
  sig { returns(T::Boolean) }
  def organization_enterprise_owned?
    organization? && self.reload.delegate_billing_to_business?
  end

  mixes_in_class_methods Couponable::ClassMethods
end
