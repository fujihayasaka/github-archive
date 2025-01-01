# typed: true
# frozen_string_literal: true

require "test_helper"

class Biztools::Businesses::Billing::RedemptionsControllerHttpTest < GitHub::IntegrationTestCase
  skip_unless :billing_enabled?

  fixtures do
    @staff = create(:staff_admin_user)
    @business = create(:business)
    @biztool_user = create(:biztools_user)
    @coupon = create(:coupon, discount: 5)
    @multi_use_coupon = create(:coupon, limit: 50)
  end

  context "GET :index" do
    test "works for staff viewer" do
      as @staff
      get "/biztools/businesses/#{@business.display_login}/billing/redemptions"

      assert_response :success
      assert_select "form[action='/biztools/coupons/apply']"
      assert_select "[data-code='#{@multi_use_coupon.code}']"
    end

    test "works for biztools viewer" do
      as @biztool_user
      get "/biztools/businesses/#{@business.display_login}/billing/redemptions"

      assert_response :success
      assert_select "form[action='/biztools/coupons/apply']"
      assert_select "[data-code='#{@multi_use_coupon.code}']"
    end

    test "works when user has no coupon redemptions" do
      as @biztool_user
      get "/biztools/businesses/#{@business.display_login}/billing/redemptions"

      assert_response :success
      assert_test_selector "redemption-history", text: /No coupon redemptions for this account/
      refute_test_selector "coupon-redemption"
    end

    test "works when user has a coupon redemption" do
      create(:coupon_redemption, billable_entity: @business, coupon: @coupon)

      as @biztool_user
      get "/biztools/businesses/#{@business.display_login}/billing/redemptions"

      assert_response :success
      assert_test_selector "redemption-history", text: /#{@coupon.code}\s+\$5\.00 for 1 month/
    end

    test "404s for non-staff, non-biztools viewers" do
      as create(:user)
      get "/biztools/businesses/#{@business.display_login}/billing/redemptions"
      assert_response :not_found
    end

    test "redirects to login for anonymous viewers" do
      get "/biztools/businesses/#{@business.display_login}/billing/redemptions"
      assert_redirected_to login_path(return_to: "http://github.com/biztools/businesses/#{@business.display_login}/billing/redemptions")
    end
  end
end
