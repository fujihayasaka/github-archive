# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessCouponsDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create :user
    @business = create(:business)
    @business_plus_card_org = create(:business_plus_organization, admin: @owner, billing_type: "card")
    @credit_card_business = create :business, :with_self_serve_payment, owners: [@owner]
    @plan_subscription = create(:billing_plan_subscription, :zuora, user: @business_plus_card_org)
    @coupon = create(:coupon, limit: 10, plan: "business_plus")
    @staff = create(:user, :staff)
    disable_feature_flag(:lowercased_opt_out_org_to_ea_upgrade)
  end

  setup do
    @business_plus_card_org.redeem_coupon(@coupon.code, actor: @owner)
  end

  context "#redeem_coupon" do
    test "returns false and does not apply anything when the business is spammy" do
      business = create(:business, :with_credit_card, spammy: true)

      assert_no_difference -> { business.coupon_redemptions.count } do
        refute business.redeem_coupon(@coupon.code)
      end
    end

    test "returns false and does not apply anything when the business is metered" do
      business = create(:business, :metered_ghec)

      assert_no_difference -> { business.coupon_redemptions.count } do
        refute business.redeem_coupon(@coupon.code)
      end
    end

    test "returns true and redeems the coupon when eligible" do
      business = create(:business, :with_credit_card)
      assert_difference -> { business.coupon_redemptions.reload.count }, 1 do
        assert business.redeem_coupon(@coupon.code, actor: @staff)
      end
    end

    test "returns true and redeems the org's coupon for the business, but only applies it for the duration that was left on the org's coupon, if the coupon_redemption_expires_at argument is passed in" do
      travel_to @business_plus_card_org.coupon_redemption.expires_at - 1.day do
        assert @credit_card_business.redeem_coupon(
          @business_plus_card_org.coupon.code,
          actor: User.ghost,
          direct_upgrade: true,
          coupon_redemption_expires_at: @business_plus_card_org.coupon_redemption.expires_at
          )

        assert_predicate @credit_card_business.reload, :has_an_active_coupon?
        assert_predicate @business_plus_card_org.reload, :has_an_active_coupon?
        assert_equal @credit_card_business.coupon, @coupon
        assert_equal @business_plus_card_org.coupon_redemption.expires_at, @credit_card_business.coupon_redemption.expires_at
        assert_equal @credit_card_business.coupon_redemption.expires_at, Time.now + 1.day
      end
    end

    test "returns true and converts the business's trial and assigns at least 1 seat" do
      free_org = create :organization, plan: GitHub::Plan.free
      trial_business = create :business, \
        :with_self_serve_payment,
        name: "Upgraded org to trial",
        upgraded_at: 2.days.ago,
        upgraded_from: free_org,
        upgraded_from_plan: free_org.plan.name
      trial_business.update_attribute :trial_expires_at, Billing::EnterpriseCloudTrial.trial_length.from_now

      assert_difference -> { trial_business.coupon_redemptions.reload.count }, 1 do
        assert trial_business.redeem_coupon(@coupon.code, actor: @staff)
      end

      assert_equal 0, trial_business.total_consumed_licenses
      # A minimum of 1 seat is required to manage seats on the business
      assert_equal 1, trial_business.seats

      assert trial_business.reload.has_an_active_coupon?
      assert trial_business.trial_completed_at
    end

    test "returns true if the business is being upgraded from a GHEC org" do
      business = create(:business, :with_credit_card, owners: [@owner])
      upgrading_org = create(:organization, plan: "business_plus", admins: [@owner])
      business.upgraded_from = upgrading_org
      business.organization_direct_upgraded!
      business.save
      refute_nil business.upgraded_from

      assert business.redeem_coupon(
        @business_plus_card_org.coupon.code,
        actor: @staff
      )

      assert_predicate business.reload, :has_an_active_coupon?
    end
  end

  context "#validate_coupon" do
    test "returns false and adds an error when the business has commercial restrictions" do
      business = create(:business, :with_credit_card)
      profile = create(:account_screening_profile, owner: business, entity_name: business.slug, first_name: nil, last_name: nil)
      profile.update!(msft_trade_screening_status: "lic_r")
      enable_feature_flag(:live_sdn_screening, business)

      refute business.validate_coupon(@coupon.code), "expected validate coupon to be false"

      assert_includes business.errors[:coupon], "can't be redeemed - lic_r"
    end

    test "returns false and adds an error when the coupon does not exist" do
      refute @business.validate_coupon("nonexistent"), "expected validate coupon to be false"

      assert_includes @business.errors[:coupon], "can't be found."
    end

    test "returns false and adds an error when the enterprise has an active coupon" do
      create(:coupon_redemption, billable_entity: @business, coupon: @coupon)
      assert_predicate @business, :has_an_active_coupon?

      coupon = create(:coupon)

      refute @business.validate_coupon(coupon.code), "expected validate coupon to be false"

      assert_includes @business.errors[:coupon], "can't be redeemed - you have an active coupon!"
    end

    test "returns false and adds an error when the enterprise account is invoiced" do
      assert_predicate @business, :invoiced?

      refute @business.validate_coupon(@coupon.code), "expected validate coupon to be false"

      assert_includes @business.errors[:coupon], "can't be redeemed with your account. Please contact support."
    end

    test "returns false and adds an error when the coupon is expired" do
      business = create(:business, :with_credit_card)

      freeze_time do
        @coupon.update!(expires_at: 5.minutes.ago)

        refute business.validate_coupon(@coupon.code, actor: @staff), "expected validate coupon to be false"

        assert_includes business.errors[:coupon], "has expired. Sorry!"
      end
    end

    test "returns true when the coupon is expired but the direct_upgrade option is passed in" do
      business = create(:business, :with_credit_card)

      freeze_time do
        @coupon.update!(expires_at: 5.minutes.ago)

        assert business.validate_coupon(@coupon.code, actor: @staff, direct_upgrade: true), "expected coupon to be valid"
      end
    end

    test "returns false when the coupon is staff only and the actor isn't" do
      refute_predicate @owner, :has_staff_role?
      @coupon.update!(staff_actor_only: true)

      refute @credit_card_business.validate_coupon(@coupon.code, actor: @owner), "expected validate_coupon to be false"
    end

    test "returns true when the coupon is staff only and the actor isn't, but the direct_upgrade option is passed in" do
      refute_predicate @owner, :has_staff_role?
      @coupon.update!(staff_actor_only: true)

      assert @credit_card_business.validate_coupon(@coupon.code, actor: @staff, direct_upgrade: true), "expected coupon to be valid"
    end

    test "returns false when the coupon has reached its limit redemption" do
      @coupon.update!(limit: 1)
      business = create(:business, :with_credit_card)
      create(:coupon_redemption, billable_entity: @business, coupon: @coupon)
      assert_predicate @business, :has_an_active_coupon?

      @coupon.reload

      assert_equal 0, @coupon.limit

      refute business.validate_coupon(@coupon.code, actor: @staff), "expected validate coupon to be false"

      assert_includes business.errors[:coupon], "can't be redeemed any more times."
    end

    test "returns false when re-use is unavailable" do
      @coupon.update!(limit: 2)
      business = create(:business, :with_credit_card)
      create(:coupon_redemption, :expired, billable_entity: business, coupon: @coupon)
      refute_predicate business, :has_an_active_coupon?

      @coupon.reload
      assert_equal 1, @coupon.limit

      refute business.validate_coupon(@coupon.code, actor: @staff), "expected validate coupon to be false"
      assert_includes business.errors[:coupon], "has already been redeemed."

      # Test true when allow_reuse is truthy
      assert business.validate_coupon(@coupon.code, allow_reuse: true, actor: @staff), "expected coupon to be valid"
    end

    test "returns true when the coupon hasn't been used on a credit card enterprise account" do
      business = create(:business, :with_credit_card)

      assert business.validate_coupon(@coupon.code, actor: @staff), "expected coupon to be valid"
    end
  end

  context "#has_an_active_coupon?" do
    test "returns true with an active coupon redemption" do
      create(:coupon_redemption, billable_entity: @business, coupon: @coupon)

      assert_predicate @business, :has_an_active_coupon?
    end

    test "returns false without a coupon redemption" do
      refute_predicate @business, :has_an_active_coupon?
    end

    test "returns false when the coupon redemption has gone stale" do
      create(:coupon_redemption, :expired, billable_entity: @business, coupon: @coupon)

      refute_predicate @business, :has_an_active_coupon?
    end
  end

  context "#coupon_redemption", skip_enterprise: true do
    test "can be batch loaded for multiple businesses efficiently" do
      business_without_coupon1, business_without_coupon2 = create_pair(:business)
      coupon1, coupon2 = create_pair(:coupon)
      coupon3 = create(:coupon, limit: 2)

      business_with_new_coupon1, business_with_new_coupon2 = create_pair(:business)
      business_with_new_coupon1.new_coupon_code = coupon1.code
      business_with_new_coupon2.new_coupon_code = coupon2.code

      business_with_coupon = create(:business)
      coupon_redemption = create(:coupon_redemption, billable_entity: business_with_coupon, coupon: coupon3)

      expired_coupon_redemption = create(:coupon_redemption, :expired, :for_business)
      business_with_expired_coupon = expired_coupon_redemption.billable_entity

      # A business whose latest redemption uses an older coupon than their earlier, expired redemption:
      prev_coupon_redemption = create(:coupon_redemption, :expired, :for_business, coupon: coupon3)
      business_with_multiple_redemptions = prev_coupon_redemption.billable_entity
      latest_coupon_redemption = create(:coupon_redemption, billable_entity: business_with_multiple_redemptions, coupon: coupon1)

      businesses = [business_without_coupon1, business_with_new_coupon1,
                    business_with_coupon, business_with_new_coupon2,
                    business_without_coupon2, business_with_expired_coupon,
                    business_with_multiple_redemptions]

      assert_query_count(2) do
        GitHub::PrefillAssociations.prefill_batch_method(businesses, :coupon_redemption)
      end

      assert_query_count(0) do
        assert_nil business_with_new_coupon1.coupon_redemption
        assert_nil business_with_new_coupon2.coupon_redemption
        assert_nil business_without_coupon1.coupon_redemption
        assert_nil business_without_coupon2.coupon_redemption
        assert_equal coupon_redemption, business_with_coupon.coupon_redemption
        assert_nil business_with_expired_coupon.coupon_redemption
        assert_equal latest_coupon_redemption, business_with_multiple_redemptions.coupon_redemption
      end
    end
  end

  context "#coupon", skip_enterprise: true do
    test "can be batch loaded for multiple businesses efficiently" do
      business_without_coupon1, business_without_coupon2 = create_pair(:business)
      coupon1, coupon2 = create_pair(:coupon)
      coupon3 = create(:coupon, limit: 2)

      business_with_new_coupon1 = create(:business)
      business_with_new_coupon1.new_coupon_code = coupon1.code
      business_with_new_coupon2 = create(:business)
      business_with_new_coupon2.new_coupon_code = coupon2.code

      business_with_coupon = create(:business)
      coupon_redemption = create(:coupon_redemption, billable_entity: business_with_coupon, coupon: coupon3)

      expired_coupon_redemption = create(:coupon_redemption, :expired, :for_business)
      business_with_expired_coupon = expired_coupon_redemption.billable_entity

      # A business whose latest redemption uses an older coupon than their earlier, expired redemption:
      prev_coupon_redemption = create(:coupon_redemption, :expired, :for_business, coupon: coupon3)
      business_with_multiple_redemptions = prev_coupon_redemption.billable_entity
      latest_coupon_redemption = create(:coupon_redemption, billable_entity: business_with_multiple_redemptions, coupon: coupon1)

      businesses = [business_without_coupon1, business_with_new_coupon1,
                    business_with_coupon, business_with_new_coupon2,
                    business_without_coupon2, business_with_expired_coupon,
                    business_with_multiple_redemptions]

      assert_query_count(1) do
        GitHub::PrefillAssociations.prefill_batch_method(businesses, :coupon)
      end

      assert_query_count(0) do
        assert_equal coupon1, business_with_new_coupon1.coupon
        assert_equal coupon2, business_with_new_coupon2.coupon
        assert_nil business_without_coupon1.coupon
        assert_nil business_without_coupon2.coupon
        assert_equal coupon_redemption.coupon, business_with_coupon.coupon
        assert_nil business_with_expired_coupon.coupon
        assert_equal latest_coupon_redemption.coupon, business_with_multiple_redemptions.coupon
      end
    end
  end

  context "#expire_active_coupon" do
    test "expires the active coupon" do
      business = create(:business)
      coupon_redemption = create(:coupon_redemption, billable_entity: business)
      business.expire_active_coupon

      assert coupon_redemption.reload.expired?, "coupon redemption should be expired"
    end

    test "does nothing if there is no active coupon" do
      business = create(:business)
      assert_nothing_raised do
        business.expire_active_coupon
      end

      assert_nil business.coupon_redemption
    end

    test "immediately downgrades the business to the free plan if it has no valid payment method" do
      business = create(:business)
      coupon_redemption = create(:coupon_redemption, billable_entity: business)
      refute_predicate business, :has_valid_payment_method?

      business.expire_active_coupon

      assert coupon_redemption.reload.expired?, "coupon redemption should be expired"
      assert_predicate business, :downgraded_to_free_plan?
    end

    test "does not downgrade the business to the free plan if it has a valid credit card linked to their enterprise account" do
      business = create(:business)
      payment_method = create(:payment_method, :zuora)
      payment_method.update_attribute(:customer, business.customer)
      coupon_redemption = create(:coupon_redemption, billable_entity: business)
      assert business.reload.has_valid_payment_method?(feature_type: :noncommercial)

      business.expire_active_coupon

      assert coupon_redemption.reload.expired?, "coupon redemption should be expired"
      refute_predicate business, :downgraded_to_free_plan?
    end

    test "does not downgrade the business to the free plan if it has a valid PayPal account linked to their enterprise account" do
      business = create(:business)
      payment_method = create(:paypal_payment_method, :zuora, paypal_email: business.owners.first.email)
      payment_method.update_attribute(:customer, business.customer)
      coupon_redemption = create(:coupon_redemption, billable_entity: business)
      assert business.reload.has_valid_payment_method?(feature_type: :noncommercial)

      business.expire_active_coupon

      assert coupon_redemption.reload.expired?, "coupon redemption should be expired"
      refute_predicate business, :downgraded_to_free_plan?
    end

    test "sends email to the business owner informing them that the coupon has expired" do
      business = create(:business)
      coupon_redemption = create(:coupon_redemption, billable_entity: business)
      education_coupon = { education_coupon: false }

      assert_difference "ActionMailer::Base.deliveries.count", 1 do
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "business_coupon_expired", args: [business, education_coupon]) do
          business.expire_active_coupon
        end
      end

      refute_predicate business.reload, :has_an_active_coupon?
    end
  end

  context "#apply_coupon_from_upgrading_org" do
    test "does nothing if the business already has a coupon" do
      business_coupon = create(:coupon, plan: "business_plus")
      @credit_card_business.redeem_coupon(business_coupon.code, actor: @owner)
      assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
      assert_predicate @business_plus_card_org, :has_an_active_coupon?
      assert_predicate @credit_card_business.reload, :has_an_active_coupon?

      refute @credit_card_business.apply_coupon_from_upgrading_org(
                  org_coupon_redemption: @business_plus_card_org.coupon_redemption
                  )

      assert_predicate @credit_card_business.reload, :has_an_active_coupon?
      assert_predicate @business_plus_card_org.reload, :has_an_active_coupon?
      assert_equal @credit_card_business.coupon, business_coupon
      assert_equal @business_plus_card_org.coupon, @coupon
    end

    test "does nothing if the organization's coupon isn't active anymore" do
      travel_to @business_plus_card_org.coupon_redemption.expires_at + 10.days do
        assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
        refute_predicate @business_plus_card_org, :has_an_active_coupon?
        refute_predicate @credit_card_business, :has_an_active_coupon?

        refute @credit_card_business.apply_coupon_from_upgrading_org(
            org_coupon_redemption: @business_plus_card_org.coupon_redemption
            )

        refute_predicate @credit_card_business.reload, :has_an_active_coupon?
        refute_predicate @business_plus_card_org.reload, :has_an_active_coupon?
      end
    end

    test "applies the coupon from the organization to the business, and records it in hydro as applied by the ghost user" do
      assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
      assert_predicate @business_plus_card_org, :has_an_active_coupon?
      refute_predicate @credit_card_business, :has_an_active_coupon?
      GlobalInstrumenter.expects(:instrument).with("billing.redeem_coupon",
        actor_id: User.ghost.id,
        business_id: @credit_card_business.id,
        coupon_id: @coupon.id,
      ).once

      assert @credit_card_business.apply_coupon_from_upgrading_org(
                org_coupon_redemption: @business_plus_card_org.coupon_redemption
                )

      assert_predicate @credit_card_business.reload, :has_an_active_coupon?
      assert_predicate @business_plus_card_org.reload, :has_an_active_coupon?
      assert_equal @credit_card_business.coupon, @coupon
    end

    test "applies the coupon, even if the coupon has expired since it was applied to the organization" do
      @coupon.update!(expires_at: 1.day.ago)
      assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
      assert_predicate @business_plus_card_org, :has_an_active_coupon?
      refute_predicate @credit_card_business, :has_an_active_coupon?

      assert @credit_card_business.apply_coupon_from_upgrading_org(org_coupon_redemption: @business_plus_card_org.coupon_redemption)

      assert_predicate @credit_card_business.reload, :has_an_active_coupon?
      assert_predicate @business_plus_card_org.reload, :has_an_active_coupon?
      assert_equal @credit_card_business.coupon, @coupon
    end

    test "applies the coupon even if the coupon's limit has been reached" do
      @coupon.update!(limit: 0)
      assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
      assert_predicate @business_plus_card_org, :has_an_active_coupon?
      refute_predicate @credit_card_business, :has_an_active_coupon?

      assert @credit_card_business.apply_coupon_from_upgrading_org(org_coupon_redemption: @business_plus_card_org.coupon_redemption)

      assert_predicate @credit_card_business.reload, :has_an_active_coupon?
      assert_predicate @business_plus_card_org.reload, :has_an_active_coupon?
      assert_equal @credit_card_business.coupon, @coupon
    end

    test "applies the coupon to the business but only applies it for the remaining duration of the coupon" do
      assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
      assert_predicate @business_plus_card_org, :has_an_active_coupon?
      refute_predicate @credit_card_business, :has_an_active_coupon?

      travel_to @business_plus_card_org.coupon_redemption.expires_at - 1.day do
        assert @credit_card_business.apply_coupon_from_upgrading_org(org_coupon_redemption: @business_plus_card_org.coupon_redemption)

        assert_predicate @credit_card_business.reload, :has_an_active_coupon?
        assert_predicate @business_plus_card_org.reload, :has_an_active_coupon?
        assert_equal @credit_card_business.coupon, @coupon
        assert_equal @business_plus_card_org.coupon_redemption.expires_at, @credit_card_business.coupon_redemption.expires_at
        assert_equal @credit_card_business.coupon_redemption.expires_at, Time.now + 1.day
      end
    end

    test "applies the coupon to the business, even if it's a staff-only coupon" do
      @coupon.update!(staff_actor_only: true)
      refute_predicate @owner, :has_staff_role?
      assert_predicate @business_plus_card_org, :eligible_for_upgrade_to_enterprise?
      assert_predicate @business_plus_card_org, :has_an_active_coupon?
      refute_predicate @credit_card_business, :has_an_active_coupon?

      assert @credit_card_business.apply_coupon_from_upgrading_org(org_coupon_redemption: @business_plus_card_org.coupon_redemption)

      assert_predicate @credit_card_business.reload, :has_an_active_coupon?
      assert_predicate @business_plus_card_org.reload, :has_an_active_coupon?
      assert_equal @credit_card_business.coupon, @coupon
    end
  end
end if GitHub.billing_enabled?
