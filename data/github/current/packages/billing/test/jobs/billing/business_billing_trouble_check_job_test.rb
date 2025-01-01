# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class BusinessBillingTroubleCheckJobTest < GitHub::TestCase
    fixtures do
      @business = create :business
      @business.customer.update billing_attempts: 3
    end

    test "displays correct notice to owners of a Business that is having billing trouble" do
      Billing::BusinessBillingTroubleCheckJob.perform_now @business

      assert_equal \
        :business_billing_trouble,
        GlobalNoticeNext.new(viewer: @business.owners.first).current_notice_name
    end
  end
end if GitHub.billing_enabled?
