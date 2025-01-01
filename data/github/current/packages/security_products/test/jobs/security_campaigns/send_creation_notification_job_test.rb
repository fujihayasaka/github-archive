# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsSendCreationNotificationJobTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    make_trusted_oauth_apps_owner

    @owner = create(:user, name: "org-owner")
    @org = create(:business_plus_organization, admin: @owner)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    @user1 = create(:user, name: "user1")
    @user2 = create(:user, name: "user2")
    @org.add_member(@user1)
    @org.add_member(@user2)

    @repo1 = create(:private_repository, owner: @org, from_example: :simple)
    @repo2 = create(:private_repository, owner: @org, from_example: :simple)

    @campaign = create(:security_campaign, organization: @org, ends_at: Time.now - 5.seconds)
  end

  setup do
    enable_feature_flag(:publish_events_to_notifyd)

    # The SecurityCampaignUser record is only created after the campaign is created, so we don't know the ID
    # of the subject in advance.
    @user_args_matcher = ->(user) do
      ->(given_args) do
        security_campaign_user = T.must(SecurityCampaigns::SecurityCampaignUser.find_by(security_campaign: @campaign, user: user))

        args = {
          actor_id: GitHub.trusted_oauth_apps_owner.id,
          subject_id: security_campaign_user.id,
          subject_klass: SecurityCampaigns::SecurityCampaignUser.name,
          context: {
            actor_id: GitHub.trusted_oauth_apps_owner.id,
            actor_login: GitHub.trusted_oauth_apps_owner.login,
            operation: "create",
          }
        }

        expected_args = [args]

        # Do not match on triggered_at
        given_args.first.delete(:triggered_at)

        given_args == expected_args
      end
    end
  end

  test "sends notifications when new campaign is created for users subscribed for alerts" do
    assert GitHub.newsies.subscribe_to_thread_types(@owner, @repo1, [SecurityAlert]).value!
    assert GitHub.newsies.subscribe_to_thread_types(@owner, @repo2, [SecurityAlert]).value!

    GitHub.newsies.get_and_update_settings(@owner) do |setting|
      setting.subscribed_settings << Newsies::HANDLER_EMAIL
    end

    assert_changes -> { SecurityCampaigns::SecurityCampaignUser.count }, from: 0, to: 1 do
      assert_enqueued_jobs 1, only: Notifyd::PublishNotifyMessageJob do
        assert_enqueued_with(job: Notifyd::PublishNotifyMessageJob, args: @user_args_matcher.call(@owner)) do
          SecurityCampaigns::SendCreationNotificationJob.perform_now(actor_id: @owner.id, campaign_id: @campaign.id, repo_ids: [@repo1.id, @repo2.id])
        end
      end
    end
  end

  test "sends correct notifications for the correct users" do
    assert GitHub.newsies.subscribe_to_thread_types(@user1, @repo1, [SecurityAlert]).value!
    assert GitHub.newsies.subscribe_to_thread_types(@user2, @repo2, [SecurityAlert]).value!

    GitHub.newsies.get_and_update_settings(@user1) do |setting|
      setting.subscribed_settings << Newsies::HANDLER_EMAIL
    end
    GitHub.newsies.get_and_update_settings(@user2) do |setting|
      setting.subscribed_settings << Newsies::HANDLER_EMAIL
    end

    assert_changes -> { SecurityCampaigns::SecurityCampaignUser.count }, from: 0, to: 2 do
      assert_enqueued_jobs 2, only: Notifyd::PublishNotifyMessageJob do
        assert_enqueued_with(job: Notifyd::PublishNotifyMessageJob, args: @user_args_matcher.call(@user1)) do
          assert_enqueued_with(job: Notifyd::PublishNotifyMessageJob, args: @user_args_matcher.call(@user2)) do
            SecurityCampaigns::SendCreationNotificationJob.perform_now(actor_id: @owner.id, campaign_id: @campaign.id, repo_ids: [@repo1.id, @repo2.id])
          end
        end
      end
    end

    assert_equal [[@campaign.id, @user1.id], [@campaign.id, @user2.id]].to_set, SecurityCampaigns::SecurityCampaignUser.pluck(:security_campaign_id, :user_id).to_set
  end

  test "does not send notifications when user is not subscribed to email notifications" do
    assert_no_changes -> { SecurityCampaigns::SecurityCampaignUser.count } do
      assert_no_enqueued_jobs only: Notifyd::PublishNotifyMessageJob do
        SecurityCampaigns::SendCreationNotificationJob.perform_now(actor_id: @owner.id, campaign_id: @campaign.id, repo_ids: [@repo1.id, @repo2.id])
      end
    end

    GlobalInstrumenter.expects(:instrument).never
  end

  test "does not fail when no repositories are returned" do
    assert_no_enqueued_jobs only: Notifyd::PublishNotifyMessageJob do
      SecurityCampaigns::SendCreationNotificationJob.perform_now(actor_id: @owner.id, campaign_id: @campaign.id, repo_ids: [])
    end
  end

  test "does not fail when no users should be notified" do
    GitHub.newsies.get_and_update_settings(@owner) do |setting|
      setting.subscribed_settings << Newsies::HANDLER_EMAIL
    end

    assert_no_enqueued_jobs only: Notifyd::PublishNotifyMessageJob do
      SecurityCampaigns::SendCreationNotificationJob.perform_now(actor_id: @owner.id, campaign_id: @campaign.id, repo_ids: [@repo1.id, @repo2.id])
    end
  end

  test "does not send notifications when the campaign is in draft" do
    @campaign.update!(published_at: nil, creation_query: "is:open")

    assert_no_enqueued_jobs only: Notifyd::PublishNotifyMessageJob do
      SecurityCampaigns::SendCreationNotificationJob.perform_now(actor_id: @owner.id, campaign_id: @campaign.id, repo_ids: [@repo1.id, @repo2.id])
    end
  end

  test "does not send notifications when the campaign is closed" do
    @campaign.update!(closed_at: 1.day.ago)

    assert_no_enqueued_jobs only: Notifyd::PublishNotifyMessageJob do
      SecurityCampaigns::SendCreationNotificationJob.perform_now(actor_id: @owner.id, campaign_id: @campaign.id, repo_ids: [@repo1.id, @repo2.id])
    end
  end
end
