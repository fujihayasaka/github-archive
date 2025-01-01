# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsOverdueSchedulerJobTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @owner = create(:user, name: "org-owner")
    @org = create(:business_plus_organization, admin: @owner)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    @long_overdue_campaign = create(:security_campaign, organization: @org, ends_at: 3.hours.ago + 1.minute)
    @just_overdue_campaign = create(:security_campaign, organization: @org, ends_at: 1.minute.ago)
    @future_overdue_campaign = create(:security_campaign, organization: @org, ends_at: 1.hour.from_now)
    @non_overdue_campaign = create(:security_campaign, organization: @org, ends_at: 1.day.from_now)
  end

  setup do
    disable_feature_flag(:security_campaigns_disable_overdue_scheduler_job)
  end

  test "is scheduled" do
    assert_predicate SecurityCampaigns::OverdueSchedulerJob, :enabled?
  end

  test "does not enqueue if disable feature flag is set" do
    enable_feature_flag(:security_campaigns_disable_overdue_scheduler_job)

    assert_enqueued_jobs(0) do
      SecurityCampaigns::OverdueSchedulerJob.perform_now
    end
  end

  test "enqueues jobs for future overdue security campaigns without previous runs" do
    assert_enqueued_jobs(2) do
      assert_enqueued_with(job: SecurityCampaigns::SendOverdueNotificationJob, args: [{ campaign_id: @future_overdue_campaign.id }], at: @future_overdue_campaign.ends_at) do
        assert_enqueued_with(job: SecurityCampaigns::PostCampaignOverdueCommentsJob, args: [{ campaign_id: @future_overdue_campaign.id }], at: @future_overdue_campaign.ends_at) do
          SecurityCampaigns::OverdueSchedulerJob.perform_now
        end
      end
    end
  end

  test "enqueues jobs for overdue security campaigns since previous run in KV" do
    CodeScanning::KV.store.set(SecurityCampaigns::OverdueSchedulerJob::LAST_EVENT_HORIZON_KEY, 1.hour.ago.to_i.to_s, expires: 1.year.from_now)

    assert_enqueued_jobs(4) do
      assert_enqueued_with(job: SecurityCampaigns::SendOverdueNotificationJob, args: [{ campaign_id: @future_overdue_campaign.id }], at: @future_overdue_campaign.ends_at) do
        assert_enqueued_with(job: SecurityCampaigns::SendOverdueNotificationJob, args: [{ campaign_id: @just_overdue_campaign.id }]) do
          assert_enqueued_with(job: SecurityCampaigns::PostCampaignOverdueCommentsJob, args: [{ campaign_id: @future_overdue_campaign.id }], at: @future_overdue_campaign.ends_at) do
            assert_enqueued_with(job: SecurityCampaigns::PostCampaignOverdueCommentsJob, args: [{ campaign_id: @just_overdue_campaign.id }]) do
              SecurityCampaigns::OverdueSchedulerJob.perform_now
            end
          end
        end
      end
    end
  end

  test "enqueues jobs for overdue security campaigns since previous run with multiple runs" do
    Timecop.freeze(3.hours.ago) do
      assert_enqueued_jobs(2) do
        SecurityCampaigns::OverdueSchedulerJob.perform_now
      end
    end

    assert_enqueued_jobs(4) do
      assert_enqueued_with(job: SecurityCampaigns::SendOverdueNotificationJob, args: [{ campaign_id: @future_overdue_campaign.id }], at: @future_overdue_campaign.ends_at) do
        assert_enqueued_with(job: SecurityCampaigns::SendOverdueNotificationJob, args: [{ campaign_id: @just_overdue_campaign.id }]) do
          assert_enqueued_with(job: SecurityCampaigns::PostCampaignOverdueCommentsJob, args: [{ campaign_id: @future_overdue_campaign.id }], at: @future_overdue_campaign.ends_at) do
            assert_enqueued_with(job: SecurityCampaigns::PostCampaignOverdueCommentsJob, args: [{ campaign_id: @just_overdue_campaign.id }]) do
              SecurityCampaigns::OverdueSchedulerJob.perform_now
            end
          end
        end
      end
    end
  end
end
