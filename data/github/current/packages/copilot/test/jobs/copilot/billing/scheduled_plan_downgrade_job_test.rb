# typed: strict
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Copilot::Billing::ScheduledPlanDowngradeJobTest < GitHub::TestCase
  include JobTestHelper
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:copilot_scheduled_plan_downgrade_job].enable
  end

  context "perform" do
    test "doesn't call subjob with flag disabled" do
      GitHub.flipper[:copilot_scheduled_plan_downgrade_job].disable

      logs = capture_logs do
        Copilot::Billing::ScheduledPlanDowngradeJob.perform_now
      end
      assert_match "Skipping Copilot::Billing::ScheduledPlanDowngradeJob", logs
    end

    test "runs job" do
      logs = capture_logs do
        Copilot::Billing::ScheduledPlanDowngradeJob.perform_now
      end
      assert_match "Loading businesses with scheduled downgrades", logs
      assert_match "gh.copilot.scheduled_plan_downgrade_job.businesses_count=\"0\"", logs
    end

    test "downgrades businesses with scheduled downgrades" do
      business = create(:copilot_business, :enterprise_plan)
      downgrading_business = create(:copilot_business, :enterprise_plan)
      downgrading_today_business = create(:copilot_business, :enterprise_plan)

      downgrading_today_business.send(:configuration).update!(pending_plan_downgrade_date: Date.today)
      downgrading_business.send(:configuration).update!(pending_plan_downgrade_date: 1.week.ago)

      logs = capture_logs do
        ActiveRecord::Base.connected_to(role: :reading) do
          Copilot::Billing::ScheduledPlanDowngradeJob.perform_now
        end
      end

      assert_match "Loading businesses with scheduled downgrades", logs
      assert_match "gh.copilot.scheduled_plan_downgrade_job.businesses_count=\"2\"", logs
      assert_equal Copilot::Business.new(business.reload).copilot_plan, "enterprise"
      assert_equal Copilot::Business.new(downgrading_business.reload).copilot_plan, "business"
      assert_equal Copilot::Business.new(downgrading_business.reload).copilot_for_dotcom_setting, "no_policy"
      assert_equal Copilot::Business.new(downgrading_today_business.reload).copilot_plan, "business"
      assert_equal Copilot::Business.new(downgrading_today_business.reload).copilot_for_dotcom_setting, "no_policy"
    end

    test "scheduled downgrades disables Copilot in github.com policy at org level" do
      downgrading_business = create(:copilot_business, :enterprise_plan)
      downgrading_business_organization = create(:copilot_for_business_enabled_organization, business: downgrading_business.business_object)

      downgrading_business.send(:configuration).update!(pending_plan_downgrade_date: 1.week.ago)

      Copilot::Organization.new(downgrading_business_organization).copilot_for_dotcom_enabled!

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::Billing::ScheduledPlanDowngradeJob.perform_now
      end

      assert_equal Copilot::Business.new(downgrading_business.reload).copilot_plan, "business"
      assert_equal Copilot::Business.new(downgrading_business.reload).copilot_for_dotcom_setting, "no_policy"
      assert_equal Copilot::Organization.new(downgrading_business_organization.reload).copilot_for_dotcom_setting, "disabled"
    end

    test "scheduled downgrades retains the trial org's Copilot in github.com policy but disables for non-trial orgs" do
      downgrading_business = create(:copilot_business, :enterprise_plan)
      downgrading_business_organization = create(:copilot_for_business_enabled_organization, business: downgrading_business.business_object)
      create(:copilot_business_trial, :organization, :recently_started, trialable: downgrading_business_organization)
      downgrading_business_organization2 = create(:copilot_for_business_enabled_organization, business: downgrading_business.business_object)

      downgrading_business.send(:configuration).update!(pending_plan_downgrade_date: 1.week.ago)

      Copilot::Organization.new(downgrading_business_organization).copilot_for_dotcom_enabled!
      Copilot::Organization.new(downgrading_business_organization2).copilot_for_dotcom_enabled!

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::Billing::ScheduledPlanDowngradeJob.perform_now
      end

      assert_equal Copilot::Business.new(downgrading_business.reload).copilot_plan, "business"
      assert_equal Copilot::Business.new(downgrading_business.reload).copilot_for_dotcom_setting, "no_policy"
      assert_equal Copilot::Organization.new(downgrading_business_organization.reload).copilot_for_dotcom_setting, "enabled"
      assert_equal Copilot::Organization.new(downgrading_business_organization2.reload).copilot_for_dotcom_setting, "disabled"
    end

    test "scheduled downgrades retains Copilot in github.com policy at org level when the feature is enabled" do
      downgrading_business = create(:copilot_business, :enterprise_plan)
      GitHub.flipper[:copilot_for_enterprise].enable
      downgrading_business_organization = create(:copilot_for_business_enabled_organization, business: downgrading_business.business_object)
      downgrading_business_organization2 = create(:copilot_for_business_enabled_organization, business: downgrading_business.business_object)

      downgrading_business.send(:configuration).update!(pending_plan_downgrade_date: 1.week.ago)

      Copilot::Organization.new(downgrading_business_organization).copilot_for_dotcom_enabled!
      Copilot::Organization.new(downgrading_business_organization2).copilot_for_dotcom_enabled!

      ActiveRecord::Base.connected_to(role: :reading) do
        Copilot::Billing::ScheduledPlanDowngradeJob.perform_now
      end

      assert_equal Copilot::Business.new(downgrading_business.reload).copilot_plan, "business"
      assert_equal Copilot::Business.new(downgrading_business.reload).copilot_for_dotcom_setting, "no_policy"
      assert_equal Copilot::Organization.new(downgrading_business_organization.reload).copilot_for_dotcom_setting, "enabled"
      assert_equal Copilot::Organization.new(downgrading_business_organization2.reload).copilot_for_dotcom_setting, "enabled"
    end
  end
end if GitHub.copilot_enabled?
