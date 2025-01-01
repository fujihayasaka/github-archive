# typed: true
# frozen_string_literal: true

require "test_helper"

class BillingRunStartJobTest < GitHub::BillingTestCase
  test "runs successfully between 4 and 5 AM PST" do
    Timecop.freeze(GitHub::Billing.timezone.parse("2022-12-13 4:00:00")) do
      Billing::DebtHunter.expects(:run_start).once

      BillingRunStartJob.perform_now
    end
  end

  test "does not run prior to the start time" do
    Timecop.freeze(GitHub::Billing.timezone.parse("2022-12-13 3:59:59")) do
      Billing::DebtHunter.expects(:run_start).never

      BillingRunStartJob.perform_now
    end
  end

  test "does not run after 5 AM PST" do
    Timecop.freeze(GitHub::Billing.timezone.parse("2022-12-13 5:00:00")) do
      Billing::DebtHunter.expects(:run_start).never

      BillingRunStartJob.perform_now
    end
  end

  test "expires coupons before starting the billing run" do
    CouponRedemption.expects(:expire!).once
    Billing::DebtHunter.expects(:run_start).once

    Timecop.freeze(GitHub::Billing.timezone.parse("2022-12-13 4:00:00")) do
      BillingRunStartJob.perform_now
    end
  end
end
