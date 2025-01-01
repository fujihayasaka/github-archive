# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class BillinglessOrgCheckJobTest < GitHub::TestCase
    test "displays correct notice when user owns an org that is missing a valid billing email" do
      admin1 = create(:user)
      admin2 = create(:user)
      org = create(:organization, admins: [admin1, admin2], plan: "bronze")

      org.update_columns(organization_billing_email: nil)
      Billing::BillinglessOrgCheckJob.perform_now(org)

      assert_equal :billingless_org, GlobalNoticeNext.new(viewer: admin1).current_notice_name
      assert_equal :billingless_org, GlobalNoticeNext.new(viewer: admin2).current_notice_name
    end
  end
end
