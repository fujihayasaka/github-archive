# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatManagement::OrgTransformFromIndividualJobTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include HydroTestHelpers
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    enable_feature_flag(:copilot_org_transform_from_individual_job)
  end

  context "org.transfrom" do
    test "does not call job when feature flag is disabled" do
      disable_feature_flag(:copilot_org_transform_from_individual_job)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgTransformFromIndividualJob.perform_now(org_id: 123)
        end
      end
      assert_match("Skipping Copilot::SeatManagement::OrgTransformFromIndividualJob", logs)
    end

    test "a user's individual subscription is cancelled when job is performed" do
      user = create(:credit_card_user)
      copilot_user = Copilot::User.new(user)
      copilot_user.allow_public_code_suggestions!
      copilot_user.disable_telemetry!
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)

      subscription_item = create(
        :billing_subscription_item,
        plan_subscription: create(:billing_plan_subscription, user: user),
        subscribable: copilot_monthly_product_uuid,
        quantity: 1,
        # Use a free trial to avoid external calls in CancelAndRefundSubscriptionItemJob
        free_trial_ends_on: GitHub::Billing.today + 30.days
      )

      perform_enqueued_jobs(only: [
        Copilot::SeatManagement::OrgTransformFromIndividualJob,
        Billing::CancelAndRefundSubscriptionItemJob
      ]) do
        Organization.transform!(user, user, plan: "business")
      end

      subscription_item.reload

      refute(subscription_item.active?)
    end

    test "a user's free user is canceled" do
      free_user = create(:copilot_free_user)
      user = free_user.user
      copilot_user = Copilot::User.new(user)
      copilot_user.allow_public_code_suggestions!
      copilot_user.disable_telemetry!

      org = Organization.transform!(user, user, plan: "business")

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgTransformFromIndividualJob.perform_now(org_id: org.id)
        end
      end

      assert_includes logs, "Destroyed FreeUser records"
      refute Copilot::FreeUser.exists?(id: free_user.id)
    end

    test "a user's limited user is canceled" do
      limited_user = create(:copilot_limited_user)
      user = limited_user.user
      copilot_user = Copilot::User.new(user)
      copilot_user.allow_public_code_suggestions!
      copilot_user.disable_telemetry!

      org = Organization.transform!(user, user, plan: "business")

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgTransformFromIndividualJob.perform_now(org_id: org.id)
        end
      end

      assert_includes logs, "Destroyed LimitedUser records"
      refute Copilot::LimitedUser.exists?(id: limited_user.id)
    end

    test "logs correctly" do
      user = create(:credit_card_user)
      copilot_user = Copilot::User.new(user)
      copilot_user.allow_public_code_suggestions!
      copilot_user.disable_telemetry!
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)

      subscription_item = create(
        :billing_subscription_item,
        :paid,
        plan_subscription: create(:billing_plan_subscription, user: user),
        subscribable: copilot_monthly_product_uuid,
        quantity: 1
      )

      GitHub.stubs(:subscribe)
      org = Organization.transform!(user, user, plan: "business")

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::SeatManagement::OrgTransformFromIndividualJob.perform_now(org_id: org.id)
        end
      end

      assert_includes logs, "Starting Copilot::SeatManagement::OrgTransformFromIndividualJob"
      assert_includes logs, "Finished Copilot::SeatManagement::OrgTransformFromIndividualJob"
      assert_includes logs, "Cleaning up copilot subscription"
      assert_log_match logs, "gh.copilot.org_transform.cancelled_subscription_item", subscription_item.id
    end

    test "in-app purchases are cancelled" do
      user = create(:credit_card_user)
      copilot_user = Copilot::User.new(user)
      copilot_user.allow_public_code_suggestions!
      copilot_user.disable_telemetry!
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, :monthly)

      subscription_item = create(
        :billing_subscription_item,
        :paid,
        :iap,
        plan_subscription: create(:billing_plan_subscription, user: user),
        subscribable: copilot_monthly_product_uuid,
        quantity: 1
      )

      GitHub.stubs(:subscribe)

      org = Organization.transform!(user, user, plan: "business")

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::SeatManagement::OrgTransformFromIndividualJob.perform_now(org_id: org.id)
      end

      perform_enqueued_jobs(only: [Billing::CancelAndRefundSubscriptionItemJob])

      assert subscription_item.reload.cancelled?
    end
  end
end if GitHub.copilot_enabled?
