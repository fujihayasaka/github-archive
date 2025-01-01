# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  module Email
    class SecurityCampaignUserHelperTest < GitHub::TestCase
      fixtures do
        @owner = create(:user, name: "org-owner")
        @org = create(:business_plus_organization, admin: @owner)

        @user = create(:user, name: "user")
        @org.add_member(@user)

        business = create(:business)
        @business_org = create(:business_plus_organization, business: business)

        @business_org.add_member(@owner)
        @business_org.add_member(@user)

        @public_repo1 = create(:public_repository, owner: @org, from_example: :simple)
        @public_repo2 = create(:public_repository, owner: @org, from_example: :simple)

        @private_repo1 = create(:private_repository, owner: @org, from_example: :simple)
        @private_repo2 = create(:private_repository, owner: @org, from_example: :simple)

        @internal_repo1 = create(:internal_repository, owner: @business_org)
        @internal_repo2 = create(:internal_repository, owner: @business_org)

        @campaign = create(:security_campaign, organization: @org)

        @explicit_access_read_user = create(:user, name: "explicit-access-read")
        @public_repo1.add_member(@explicit_access_read_user, action: :read)
        @private_repo1.add_member(@explicit_access_read_user, action: :read)
        @internal_repo1.add_member(@explicit_access_read_user, action: :read)

        @user_with_no_access = create(:user, name: "user-with-no-access")

        create(:security_campaign_alert, repository: @public_repo1, security_campaign: @campaign, logical_alert_number: 1)
        create(:security_campaign_alert, repository: @public_repo2, security_campaign: @campaign, logical_alert_number: 2)

        create(:security_campaign_alert, repository: @private_repo1, security_campaign: @campaign, logical_alert_number: 1)
        create(:security_campaign_alert, repository: @private_repo2, security_campaign: @campaign, logical_alert_number: 2)

        create(:security_campaign_alert, repository: @internal_repo1, security_campaign: @campaign, logical_alert_number: 1)
        create(:security_campaign_alert, repository: @internal_repo2, security_campaign: @campaign, logical_alert_number: 2)
      end

      def subscribe_user_to_all_repo_types(user:)
        GitHub.newsies.subscribe_to_list(user, @private_repo1)
        GitHub.newsies.subscribe_to_list(user, @public_repo1)
        GitHub.newsies.subscribe_to_list(user, @internal_repo1)
      end

      def subscribe_user_to_thread_type(user:, thread_type:)
        GitHub.newsies.subscribe_to_thread_types(user, @private_repo1, [thread_type])
        GitHub.newsies.subscribe_to_thread_types(user, @public_repo1, [thread_type])
        GitHub.newsies.subscribe_to_thread_types(user, @internal_repo1, [thread_type])
      end

      test "works for org admin and subscribed to all repo events" do
        subscribe_user_to_all_repo_types(user: @owner)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @owner, security_campaign: @campaign)

        assert_same_elements [@private_repo1.id, @public_repo1.id, @internal_repo1.id], enabled_repository_ids
      end

      test "works for org member and subscribed to all repo events" do
        subscribe_user_to_all_repo_types(user: @user)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @user, security_campaign: @campaign)

        assert_same_elements [@private_repo1.id, @public_repo1.id, @internal_repo1.id], enabled_repository_ids
      end

      test "works for user outside of org with read access to repo and subscribed for all repo events" do
        subscribe_user_to_all_repo_types(user: @explicit_access_read_user)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @explicit_access_read_user, security_campaign: @campaign)

        assert_same_elements [@private_repo1.id, @public_repo1.id, @internal_repo1.id], enabled_repository_ids
      end

      test "works for user outside of org with no access to repo and subscribed for all repo events" do
        subscribe_user_to_all_repo_types(user: @user_with_no_access)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @user_with_no_access, security_campaign: @campaign)

        assert_same_elements [@public_repo1.id], enabled_repository_ids
      end

      test "works for org admin and subscribed to security alerts only" do
        subscribe_user_to_thread_type(user: @owner, thread_type: SecurityAlert)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @owner, security_campaign: @campaign)

        assert_same_elements [@private_repo1.id, @public_repo1.id, @internal_repo1.id], enabled_repository_ids
      end

      test "works for org member and subscribed to security alerts only" do
        subscribe_user_to_thread_type(user: @user, thread_type: SecurityAlert)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @user, security_campaign: @campaign)

        assert_same_elements [@private_repo1.id, @public_repo1.id, @internal_repo1.id], enabled_repository_ids
      end

      test "works for user with read access and subscribed to security alerts only" do
        subscribe_user_to_thread_type(user: @explicit_access_read_user, thread_type: SecurityAlert)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @explicit_access_read_user, security_campaign: @campaign)

        assert_same_elements [@private_repo1.id, @public_repo1.id, @internal_repo1.id], enabled_repository_ids
      end

      test "works for user with no access and subscribed to security alerts only" do
        subscribe_user_to_thread_type(user: @user_with_no_access, thread_type: SecurityAlert)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @user_with_no_access, security_campaign: @campaign)

        assert_same_elements [@public_repo1.id], enabled_repository_ids
      end

      test "works for org admin and subscribed to other types of events" do
        subscribe_user_to_thread_type(user: @owner, thread_type: PullRequest)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @owner, security_campaign: @campaign)

        assert_same_elements [], enabled_repository_ids
      end

      test "works for org member and subscribed to other types of events" do
        subscribe_user_to_thread_type(user: @user, thread_type: PullRequest)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @user, security_campaign: @campaign)

        assert_same_elements [], enabled_repository_ids
      end

      test "works for user with read access and subscribed to other types of events" do
        subscribe_user_to_thread_type(user: @explicit_access_read_user, thread_type: PullRequest)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @explicit_access_read_user, security_campaign: @campaign)

        assert_same_elements [], enabled_repository_ids
      end

      test "works for user with no access and subscribed to other types of events" do
        subscribe_user_to_thread_type(user: @user_with_no_access, thread_type: PullRequest)

        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @user_with_no_access, security_campaign: @campaign)

        assert_same_elements [], enabled_repository_ids
      end

      test "works for org admin and not subscribed to any events" do
        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @owner, security_campaign: @campaign)

        assert_same_elements [], enabled_repository_ids
      end

      test "works for org member and not subscribed to any events" do
        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @user, security_campaign: @campaign)

        assert_same_elements [], enabled_repository_ids
      end

      test "works for user with read access and not subscribed to any events" do
        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @explicit_access_read_user, security_campaign: @campaign)

        assert_same_elements [], enabled_repository_ids
      end

      test "works for user with no access and not subscribed to any events" do
        enabled_repository_ids = Notifyd::Email::SecurityCampaignUserHelper.enabled_repository_ids(user: @user_with_no_access, security_campaign: @campaign)

        assert_same_elements [], enabled_repository_ids
      end
    end
  end
end
