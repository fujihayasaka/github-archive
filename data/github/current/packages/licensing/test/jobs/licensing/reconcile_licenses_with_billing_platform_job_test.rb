# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Licensing::ReconcileLicensesWithBillingPlatformJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @user = create(:user)
    @extra_user = create(:user)
    @org = create(:organization)
    @org.add_member(@user)

    @business = create(:business, organizations: [@org])
    @user.business_user_account.update!(ghec_license: :enterprise_license)
  end

  test "adds a license missing from billing platform" do
    Billing::Platform::Api::Client.any_instance
      .stubs(:get_subscribed_items)
      .returns({
         subscribedItems: []
      })

    BusinessUserAccount.any_instance.expects(:emit_added_license_billing_message).once
    Licensing::ReconcileLicensesWithBillingPlatformJob.new.perform(@business)
  end

  test "removes an extra license in billing platform" do
    Billing::Platform::Api::Client.any_instance
      .stubs(:get_subscribed_items)
      .returns({
         subscribedItems: [{
          subscriptionId: @extra_user.id,
          status: true,
          subscribedAt: (::GitHub::Billing.today.beginning_of_month.beginning_of_day - 1.day).to_i * 1000,
          lastBilledForAt: 0
        }, {
          subscriptionId: @user.id,
          status: true,
          subscribedAt: (::GitHub::Billing.today.beginning_of_month.beginning_of_day - 1.day).to_i * 1000,
          lastBilledForAt: 0
        }]
      })

    BusinessUserAccount.any_instance.expects(:emit_removed_license_billing_message).once
    Licensing::ReconcileLicensesWithBillingPlatformJob.new.perform(@business)
  end
end if GitHub.billing_enabled?
