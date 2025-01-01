# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsSendOverdueNotificationJobTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @owner = create(:user, name: "org-owner")
    @org = create(:business_plus_organization, admin: @owner)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    @repo1 = create(:private_repository, owner: @org, from_example: :simple)
    @repo2 = create(:private_repository, owner: @org, from_example: :simple)
    @repo3 = create(:private_repository, owner: @org, from_example: :simple)

    @campaign = create(:security_campaign, organization: @org, ends_at: Time.now - 5.seconds)
    @campaign_repo1 = create(:security_campaign_repository, repository: @repo1, security_campaign: @campaign)
    @campaign_repo2 = create(:security_campaign_repository, repository: @repo2, security_campaign: @campaign)
    @campaign_repo3 = create(:security_campaign_repository, repository: @repo3, security_campaign: @campaign)

    create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign, logical_alert_number: 1)
    create(:security_campaign_alert, repository: @repo2, security_campaign: @campaign, logical_alert_number: 2)
    create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign, logical_alert_number: 3)
    create(:security_campaign_alert, repository: @repo2, security_campaign: @campaign, logical_alert_number: 3)
    create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign, logical_alert_number: 4)
    create(:security_campaign_alert, repository: @repo3, security_campaign: @campaign, logical_alert_number: 4)
  end

  setup do
    GitHub.flipper[:security_campaigns_disable_send_overdue_notification_job].disable
    GitHub.flipper[:publish_events_to_notifyd].enable

    GitHub::Turboscan.stubs(:counts_by_repo_numbers).with({
      owner_ids: [@org.id],
      repo_numbers: [
        Turboscan::Proto::RepoNumber.new({
          repository_id: @repo1.id,
          number: 1,
        }),
        Turboscan::Proto::RepoNumber.new({
          repository_id: @repo1.id,
          number: 3,
        }),
        Turboscan::Proto::RepoNumber.new({
          repository_id: @repo1.id,
          number: 4,
        }),
        Turboscan::Proto::RepoNumber.new({
          number: 2,
          repository_id: @repo2.id,
        }),
        Turboscan::Proto::RepoNumber.new({
          number: 3,
          repository_id: @repo2.id,
        }),
        Turboscan::Proto::RepoNumber.new({
          number: 4,
          repository_id: @repo3.id,
        }),
      ],
    }).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::CountsByRepoNumbersResponse.new(
          repository_counts: [
            Turboscan::Proto::CountsByRepoNumbersResponse::RepositoryCounts.new(
              repository_id: @repo1.id,
              open_count: 2,
              closed_count: 1,
            ),
            Turboscan::Proto::CountsByRepoNumbersResponse::RepositoryCounts.new(
              repository_id: @repo2.id,
              open_count: 2,
              closed_count: 0,
            ),
            Turboscan::Proto::CountsByRepoNumbersResponse::RepositoryCounts.new(
              repository_id: @repo3.id,
              open_count: 0,
              closed_count: 1,
            ),
          ]
        )
      )
    )
  end

  test "does not send notification if disable feature flag is set" do
    GitHub.flipper[:security_campaigns_disable_send_overdue_notification_job].enable

    assert_enqueued_jobs(0) do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "sends notification for open alerts in repos" do
    Timecop.freeze do
      assert_enqueued_jobs(2) do
        assert_enqueued_with(job: Notifyd::PublishNotifyMessageJob, args: expected_args_for(@campaign_repo1, 2)) do
          assert_enqueued_with(job: Notifyd::PublishNotifyMessageJob, args: expected_args_for(@campaign_repo2, 2)) do
            SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
          end
        end
      end
    end
  end

  test "does not fail if security campaign does not exist" do
    @campaign.destroy!

    assert_enqueued_jobs(0) do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "does not send notification if the campaign due date is too far in the future" do
    @campaign.update!(ends_at: 3.hours.from_now)

    assert_enqueued_jobs(0) do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "does not fail when no repositories with open alerts are returned" do
    GitHub::Turboscan.expects(:counts_by_repo_numbers).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::CountsByRepoNumbersResponse.new(
          repository_counts: [
            Turboscan::Proto::CountsByRepoNumbersResponse::RepositoryCounts.new(
              repository_id: @repo1.id,
              open_count: 0,
              closed_count: 3,
            ),
            Turboscan::Proto::CountsByRepoNumbersResponse::RepositoryCounts.new(
              repository_id: @repo2.id,
              open_count: 0,
              closed_count: 2,
            ),
            Turboscan::Proto::CountsByRepoNumbersResponse::RepositoryCounts.new(
              repository_id: @repo3.id,
              open_count: 0,
              closed_count: 1,
            ),
          ]
        )
      )
    )

    assert_enqueued_jobs(0) do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "fails when the Turboscan call fails" do
    GitHub::Turboscan.expects(:counts_by_repo_numbers).once.returns(
      Twirp::ClientResp.new(
        error: Twirp::Error.new(:internal, "Internal error"),
      )
    )

    assert_raises_with_message(StandardError, "Internal error") do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "fails when the Turboscan result is nil" do
    GitHub::Turboscan.expects(:counts_by_repo_numbers).once.returns(nil)

    assert_raises_with_message(StandardError, "No response when fetching alerts") do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "fails when the Turboscan data is nil" do
    GitHub::Turboscan.expects(:counts_by_repo_numbers).returns(
      Twirp::ClientResp.new(
        data: nil,
      )
    )

    assert_raises_with_message(StandardError, "No data when fetching alerts") do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  def expected_args_for(campaign_repo, open_count)
    [{
      actor_id: campaign_repo.security_campaign.manager.id,
      subject_id: campaign_repo.id,
      subject_klass: SecurityCampaigns::SecurityCampaignRepository.name,
      context: {
        actor_id: campaign_repo.security_campaign.manager.id,
        actor_login: campaign_repo.security_campaign.manager.login,
        operation: "overdue",
        open_alerts_count: open_count,
      },
      triggered_at: Time.now,
    }]
  end
end
