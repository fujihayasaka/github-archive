# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::Billing::Organizations::ScheduledPlanDowngradeJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:copilot_mixed_licenses].enable
  end

  context "perform" do
    test "runs job" do
      logs = capture_logs do
        Copilot::Billing::Organizations::ScheduledPlanDowngradeJob.perform_now
      end
      assert_match "Loading organizations with scheduled downgrades", logs
      assert_match "gh.copilot.scheduled_plan_downgrade_job.orgs_count=\"0\"", logs
    end

    test "downgrades organizations with scheduled downgrades" do
      business = create(:copilot_business, :enterprise_plan).__getobj__
      downgrading_org1 = create(:copilot_for_business_enabled_organization, business: business)
      downgrading_org2 = create(:copilot_for_business_enabled_organization, business: business)

      Copilot::Business.new(business).copilot_for_dotcom_enabled!

      just_an_org = create(:copilot_for_business_enabled_organization, business: business)

      Copilot::Configuration
        .where(
          configurable_id: downgrading_org1.id,
          configurable_type: "Organization"
        )
        .first!
        .update!(pending_plan_downgrade_date: 1.week.ago, copilot_plan: :enterprise)

      Copilot::Configuration
        .where(
          configurable_id: downgrading_org2.id,
          configurable_type: "Organization"
        )
        .first!
        .update!(pending_plan_downgrade_date: Date.today, copilot_plan: :enterprise)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::Organizations::ScheduledPlanDowngradeJob.perform_now
        end
      end

      assert_match "Loading organizations with scheduled downgrades", logs
      assert_match "gh.copilot.scheduled_plan_downgrade_job.orgs_count=\"2\"", logs

      assert Copilot::Organization.new(downgrading_org1.reload).copilot_plan_business?
      assert Copilot::Organization.new(downgrading_org2.reload).copilot_plan_business?

      assert_equal Copilot::Organization.new(downgrading_org1.reload).copilot_for_dotcom_setting, "enabled"
      assert_equal Copilot::Organization.new(downgrading_org2.reload).copilot_for_dotcom_setting, "enabled"

      assert Copilot::Organization.new(just_an_org.reload).dotcom_chat_enabled?
    end

    test "sends an email to admins and users when copilot plan is downgraded" do
      business = create(:copilot_business, :enterprise_plan).__getobj__
      downgrading_org = create(:copilot_for_business_enabled_organization, business: business)
      seat = create(:copilot_seat, organization: downgrading_org)
      mailer = mock
      mailer.stubs(:deliver_later)

      Copilot::Configuration
        .where(
          configurable_id: downgrading_org.id,
          configurable_type: "Organization"
        )
        .first!
        .update!(pending_plan_downgrade_date: 1.week.ago, copilot_plan: :enterprise)


      CopilotForBusinessMailer.expects(:welcome_org_admins).with(downgrading_org).returns(mailer).once
      CopilotForBusinessMailer.expects(:welcome_individual).with(downgrading_org, seat.assigned_user).returns(mailer).once

      capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::Organizations::ScheduledPlanDowngradeJob.perform_now
        end
      end

      assert Copilot::Organization.new(downgrading_org.reload).copilot_plan_business?
    end
  end
end if GitHub.copilot_enabled?
