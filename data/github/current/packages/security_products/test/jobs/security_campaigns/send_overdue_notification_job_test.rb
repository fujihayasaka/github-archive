# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsSendOverdueNotificationJobTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    make_trusted_oauth_apps_owner

    @owner = create(:user, name: "org-owner")
    @org = create(:business_plus_organization, admin: @owner)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    @repo1 = create(:private_repository, owner: @org, from_example: :simple)
    @repo2 = create(:private_repository, owner: @org, from_example: :simple)
    @repo3 = create(:private_repository, owner: @org, from_example: :simple)

    @user1 = create(:user, name: "user1")
    @user2 = create(:user, name: "user2")
    # we want to make sure that this user is not included in the notification
    @user3 = create(:user, name: "user3")
    @org.add_member(@user1)
    @org.add_member(@user2)

    @campaign = create(:security_campaign, organization: @org, ends_at: Time.now - 5.seconds)

    @campaign_user1 = create(:security_campaign_user, user: @user1, security_campaign: @campaign)
    @campaign_user2 = create(:security_campaign_user, user: @user2, security_campaign: @campaign)
    @campaign_user3 = create(:security_campaign_user, user: @user3, security_campaign: @campaign)
  end

  setup do
    disable_feature_flag(:security_campaigns_disable_send_overdue_notification_job)
    enable_feature_flag(:publish_events_to_notifyd)

    GitHub::Turboscan.stubs(:counts_by_repo).with({
      owner_ids: [@org.id],
      filter: {
        security_campaign_ids: [@campaign.id],
      },
    }).returns(Twirp::ClientResp.new(
      data: Turboscan::Proto::CountsByRepoResponse.new({
        open_count: 1,
        closed_count: 10,
        repository_counts: [
          Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
            repository_id: @repo1.id,
            open_count: 2,
            closed_count: 1,
          }),
          Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
            repository_id: @repo2.id,
            open_count: 2,
            closed_count: 0,
          }),
          Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
            repository_id: @repo3.id,
            open_count: 0,
            closed_count: 1,
          }),
        ],
      })
    ))
  end

  test "does not send notification if disable feature flag is set" do
    enable_feature_flag(:security_campaigns_disable_send_overdue_notification_job)

    assert_enqueued_jobs(0) do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "sends notification for open alerts in repos per user and campaign for user with repo access" do
    assert GitHub.newsies.subscribe_to_thread_types(@user1, @repo1, [SecurityAlert]).value!
    assert GitHub.newsies.subscribe_to_thread_types(@user2, @repo2, [SecurityAlert]).value!
    GitHub.newsies.get_and_update_settings(@user1) do |setting|
      setting.subscribed_settings << Newsies::HANDLER_EMAIL
    end
    GitHub.newsies.get_and_update_settings(@user2) do |setting|
      setting.subscribed_settings << Newsies::HANDLER_EMAIL
    end

    alert_counts_by_repo = { @repo1.id.to_s => 2, @repo2.id.to_s => 2, @repo3.id.to_s => 0 }

    Timecop.freeze do
      assert_enqueued_jobs(2) do
        assert_enqueued_with(job: Notifyd::PublishNotifyMessageJob, args: expected_args_for_user(@campaign, @campaign_user1, alert_counts_by_repo)) do
          assert_enqueued_with(job: Notifyd::PublishNotifyMessageJob, args: expected_args_for_user(@campaign, @campaign_user2, alert_counts_by_repo)) do
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

  test "does not send notification if the campaign is closed" do
    @campaign.update!(closed_at: 1.day.ago)
    assert_enqueued_jobs(0) do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "does not send notification if the campaign is in draft" do
    @campaign.update!(published_at: nil, creation_query: "is:open")
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
    GitHub::Turboscan.expects(:counts_by_repo).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::CountsByRepoResponse.new(
          repository_counts: [
            Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new(
              repository_id: @repo1.id,
              open_count: 0,
              closed_count: 3,
            ),
            Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new(
              repository_id: @repo2.id,
              open_count: 0,
              closed_count: 2,
            ),
            Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new(
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
    GitHub::Turboscan.expects(:counts_by_repo).once.returns(
      Twirp::ClientResp.new(
        error: Twirp::Error.new(:internal, "Internal error"),
      )
    )

    assert_raises_with_message(StandardError, "Internal error") do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "fails when the Turboscan result is nil" do
    GitHub::Turboscan.expects(:counts_by_repo).once.returns(nil)

    assert_raises_with_message(StandardError, "No response when fetching alerts") do
      SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "does not error if org has been deleted" do
    @org.destroy

    assert_no_error_reported do
      assert_no_enqueued_jobs(only: Notifyd::PublishNotifyMessageJob) do
        SecurityCampaigns::SendOverdueNotificationJob.perform_now(campaign_id: @campaign.id)
      end
    end
  end

  def expected_args_for_user(campaign, campaign_user, alert_counts_by_repo)
    [{
      actor_id: GitHub.trusted_oauth_apps_owner.id,
      subject_id: campaign_user.id,
      subject_klass: SecurityCampaigns::SecurityCampaignUser.name,
      context: {
        actor_id: GitHub.trusted_oauth_apps_owner.id,
        actor_login: GitHub.trusted_oauth_apps_owner.login,
        operation: "overdue",
        alert_counts_by_repo:,
        repo_counts_by_repo: alert_counts_by_repo.to_json,
      },
      triggered_at: Time.now,
    }]
  end
end
