# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing
  class BillingEmailCheckJobTest < GitHub::TestCase
    test "displays correct notice when user is a user with an invalid billing email" do
      user = create(:user)

      user.emails.first.update_columns(email: "not valid")
      user = User.find(user.id) # instantiate fresh object to clear memoization
      Billing::BillingEmailCheckJob.perform_now(user)

      assert_equal :billing_email, GlobalNoticeNext.new(viewer: user).current_notice_name
    end

    test "displays notice for all admins of an org with an invalid billing email" do
      admin1 = create(:user)
      admin2 = create(:user)
      org = create(:organization, admins: [admin1, admin2])

      org.update_columns(organization_billing_email: "not valid")
      Billing::BillingEmailCheckJob.perform_now(org)

      assert_equal :billing_email, GlobalNoticeNext.new(viewer: admin1).current_notice_name
      assert_equal :billing_email, GlobalNoticeNext.new(viewer: admin2).current_notice_name
    end
  end
end
