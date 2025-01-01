# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponExpiringWhenActiveTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @user   = create(:user, plan: "small")
      @coupon = create(:coupon, discount: "$5")
    end

    test "keeps a user with CC info on the same plan" do
      user = create(:credit_card_user, plan: "pro")
      coupon = create :coupon
      user.redeem_coupon(coupon)

      assert user.expire_active_coupon
      assert_equal GitHub::Plan.pro, user.plan
    end

    test "expiring a coupon that also ends a customers trial" do
      user = create(:organization, plan: "business_plus")
      # Coupons associated to a plan trigger CouponDependency#end_trial_on_plan_change
      coupon = create :coupon, plan: "business_plus"
      user.redeem_coupon(coupon)

      assert user.expire_active_coupon
      assert_equal GitHub::Plan.free, user.plan
    end

    test "deletes two week notice about expiring coupon" do
      # setup a coupon that will trigger a notice for expiry
      @user.redeem_coupon(@coupon)
           .update_attribute(:expires_at, GitHub::Billing.now + 14.days) # just right
      User.notify_coupon_expiring_in_two_weeks

      assert_includes @user.notices_for_dashboard, "coupon_will_expire"

      @user.expire_active_coupon
      refute_includes @user.notices_for_dashboard, "coupon_will_expire"
    end

    test "deletes one week notice about expiring coupon" do
      # setup a coupon that will trigger a notice for expiry
      @user.redeem_coupon(@coupon)
           .update_attribute(:expires_at, GitHub::Billing.now + 7.days) # just right
      User.notify_coupon_expiring_in_one_week

      assert_includes @user.notices_for_dashboard, "coupon_will_expire"

      @user.expire_active_coupon
      refute_includes @user.notices_for_dashboard, "coupon_will_expire"
    end

    test "notifies the organization admins when a coupon has expired if the organization is owned by a self-serve enterprise" do
      organization = create :business_plus_organization, admins: [@user]
      coupon = create(:coupon, discount: "$5")
      organization.redeem_coupon(coupon)

      business = create(:business, owners: [@user], billing_email: "billing@example.com")
      business.customer.update_attribute(:billing_type, "card")
      payment_method = create(:payment_method, :zuora)
      payment_method.update_attribute(:customer, business.customer)
      assert_predicate business, :has_valid_payment_method?

      business.add_organization(organization, actor: @user)

      assert_difference "ActionMailer::Base.deliveries.count", 1 do
        assert_performed_email(mailer: "BillingNotificationsMailer", action: "coupon_removed_from_enterprise_owned_organization", args: [organization, business]) do
          organization.expire_active_coupon
        end
      end
    end

    test "does not notify organization admins when a coupon has expired if the organization is not enterprise-owned" do
      organization = create :business_plus_organization, admins: [@user]
      coupon = create(:coupon, discount: "$5")
      organization.redeem_coupon(coupon)

      payment_method = create(:payment_method, :zuora)
      payment_method.update_attribute(:customer, organization.customer)
      assert_predicate organization, :has_valid_payment_method?

      only = [ApplicationDeliveryJob]
      perform_enqueued_jobs(only: only) do
        organization.expire_active_coupon
      end

      assert_empty ActionMailer::Base.deliveries
    end

    test "does not notify organization admins when a coupon has expired if the organization is enterprise-owned but quiet is true" do
      organization = create :business_plus_organization, admins: [@user]
      coupon = create(:coupon, discount: "$5")
      organization.redeem_coupon(coupon)

      business = create(:business, owners: [@user])
      business.add_organization(organization, actor: @user)

      only = [ApplicationDeliveryJob]
      perform_enqueued_jobs(only: only) do
        organization.expire_active_coupon(quiet: true)
      end

      assert_empty ActionMailer::Base.deliveries
    end
  end
end
