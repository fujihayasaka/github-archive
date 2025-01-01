# typed: true
# frozen_string_literal: true

require "test_helper"

if GitHub.billing_enabled?
  class CouponInstrumentationTest < GitHub::TestCase
    include GitHub::BillingTest

    fixtures do
      @user = create(:user)
      @org  = create :organization, admin: @user
    end

    setup do
      @service     = Instrumentation::MockService.new
      @old_service = GitHub.instrumentation_service
      # This is defined for tests in test_helpers/instrumentation_helper.rb
      GitHub.instrumentation_service = @service
    end

    teardown do
      GitHub.instrumentation_service = @old_service
    end

    test "generate an audit log with the plan change" do
      coupon = create(:coupon, code: "foobar", discount: "100%", plan: "gold")

      @org.redeem_coupon(coupon, actor: @user)

      assert @service.events
        .select { |name, _payload, _context, *_| name == "account.plan_change" }
        .pop, "not instrumented"
    end

    test "generates an audit entry with the user as actor" do
      coupon = create(:coupon, code: "foobar", discount: "100%", plan: "large")

      @user.redeem_coupon coupon.code

      assert @service.events
        .select { |name, _payload, _context, *_| name == "account.plan_change" }
        .pop, "not instrumented"
    end

    test "does not generate an plan change audit log, when requested" do
      coupon = create(:coupon, code: "foobar", discount: "100%", plan: "gold")

      @org.redeem_coupon(coupon, actor: @user, instrument: false)

      refute @service.events
        .select { |name, _payload, _context, *_| name == "account.plan_change" }
        .pop
    end
  end
end
