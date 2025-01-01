# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::BusinessTrials::UpgradeCleanupJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include HydroTestHelpers

  context "perform" do
    test "it cleans up free users and cancels subscriptions" do
      freeze_time do
        business = create(:business)
        organization = create(:organization, business: business)

        free_user = create(:user)
        create(:copilot_free_user, user: free_user)
        organization.add_member(free_user)
        free_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: free_user)
        free_seat_assignment.convert_to_seats

        cfi_user = create(:user)
        subscription = create(
          :billing_subscription_item,
          :with_copilot_product_uuid,
          plan_subscription: create(:billing_plan_subscription, user: cfi_user),
        )
        organization.add_member(cfi_user)
        cfi_seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: cfi_user)
        cfi_seat_assignment.convert_to_seats

        user = create(:user)
        organization.add_member(user)
        seat_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user)
        seat_assignment.convert_to_seats

        ::Billing::Public::SubscriptionItem
        .expects(:cancel_and_refund)
        .with(
          account: cfi_user,
          organization: organization,
          product: subscription.product_uuid,
          allow_cancelling_iap: true
        )
        .returns(GitHub::Result.new { true })
        .once

        assert_changes -> { Copilot::FreeUser.count }, from: 1, to: 0 do
          ActiveRecord::Base.connected_to(role: :reading) do
            Copilot::BusinessTrials::UpgradeCleanupJob.perform_now(organization.id)
          end
        end
      end
    end
  end
end if GitHub.copilot_enabled?
