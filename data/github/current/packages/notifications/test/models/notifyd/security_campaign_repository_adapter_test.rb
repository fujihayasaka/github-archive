# typed: true
# frozen_string_literal: true

require "test_helper"

module Notifyd
  class SecurityCampaignRepositoryAdapterTest < GitHub::TestCase
    include NotifydTestHelper

    fixtures do
      @owner = create(:user, name: "org-owner")
      @org = create(:business_plus_organization, admin: @owner)

      @repo = create(:private_repository, owner: @org, from_example: :simple)
      @campaign = create(:security_campaign, organization: @org)
      @campaign_repository = create(:security_campaign_repository, repository: @repo, security_campaign: @campaign)

      @member = create(:user, name: "org-member")
      @org.add_member(@member)

      @repo_admin = create(:user, name: "repo-admin")
      @org.add_member(@repo_admin)
      @repo.add_member(@repo_admin, action: :admin)

      @explicit_access_read_user = create(:user, name: "explicit-access-read")
      @org.add_member(@explicit_access_read_user)
      @repo.add_member(@explicit_access_read_user, action: :read)

      @explicit_access_write_user = create(:user, name: "explicit-access-write")
      @org.add_member(@explicit_access_write_user)
      @repo.add_member(@explicit_access_write_user, action: :write)

      @rando = create(:user)
    end

    setup do
      @context = {
        actor_id: @owner.id,
        actor_login: @owner.display_login,
      }
      @adapter = Notifyd::SecurityCampaignRepositoryAdapter.new(@campaign_repository, @context)
    end

    context "#matches" do
      test "matches a SecurityCampaignRepository" do
        assert_predicate @adapter, :matches?
      end

      test "matches without an actor" do
        # The actor is in the context and we cannot assume the context is always present
        adapter = Notifyd::SecurityCampaignRepositoryAdapter.new(@campaign_repository)
        assert_predicate adapter, :matches?
      end
    end

    context "#notification_id" do
      test "returns the permalink without host" do
        assert_equal @campaign_repository.permalink(include_host: false), @adapter.notification_id
        refute_equal @campaign_repository.permalink, @adapter.notification_id
      end
    end

    context "#repository_id" do
      test "matches the repository ID" do
        assert_equal @repo.id, @adapter.repository_id
      end
    end

    context "#authzd_attributes" do
      test "matches the permission wrapper attributes" do
        assert_equal @campaign_repository.permissions_wrapper.serialized_subject_attributes, @adapter.authzd_attributes
      end
    end

    context "#saml_enforcement" do
      test "is enforced for the organization" do
        assert_equal({ organization_id: @org.id }, @adapter.saml_enforcement)
      end
    end

    context "#email_layout" do
      test "is rendered for create" do
        adapter = Notifyd::SecurityCampaignRepositoryAdapter.new(@campaign_repository, @context.merge(
          operation: Notifyd::Operations::SecurityCampaignRepositoryOperation::Create.serialize,
        ))

        assert_kind_of Notifyd::Proto::Layouts::Email::Basic, adapter.email_layout
      end

      test "is rendered for overdue" do
        adapter = Notifyd::SecurityCampaignRepositoryAdapter.new(@campaign_repository, @context.merge(
          operation: Notifyd::Operations::SecurityCampaignRepositoryOperation::Overdue.serialize,
          open_alerts_count: 5,
        ))

        assert_kind_of Notifyd::Proto::Layouts::Email::Basic, adapter.email_layout
      end

      test "raises for missing operation" do
        assert_raises_with_message(ArgumentError, /Unknown operation/) do
          @adapter.email_layout
        end
      end
    end

    context "#related_topics" do
      test "returns the related topics" do
        assert_same_elements [
          { type: "repository", value: @repo.id.to_s },
          { type: "security_campaign_repository", value: @campaign_repository.id.to_s },
          { type: "security_campaign", value: @campaign.id.to_s },
        ], @adapter.related_topics
      end
    end

    context "#explicit_recipients" do
      test "is empty when no-one is watching the repository" do
        assert_equal [], @adapter.explicit_recipients
      end

      test "returns users that are watching the repository" do
        assert @owner.watch_repo(@repo, enqueue: false)
        assert @member.watch_repo(@repo, enqueue: false)
        assert @repo_admin.watch_repo(@repo, enqueue: false)
        assert @explicit_access_read_user.watch_repo(@repo, enqueue: false)
        assert @explicit_access_write_user.watch_repo(@repo, enqueue: false)

        GitHub.newsies.get_and_update_settings(@owner) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@member) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@repo_admin) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@explicit_access_read_user) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@explicit_access_write_user) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end

        assert_equal [
          {
            reason: "security_alert",
            users: [@owner, @member, @repo_admin, @explicit_access_read_user, @explicit_access_write_user],
          },
        ], @adapter.explicit_recipients
      end

      test "returns users that are watching security alerts on the repository" do
        assert GitHub.newsies.subscribe_to_thread_types(@owner, @repo, [SecurityAlert]).value!
        assert GitHub.newsies.subscribe_to_thread_types(@member, @repo, [SecurityAlert]).value!
        assert GitHub.newsies.subscribe_to_thread_types(@repo_admin, @repo, [SecurityAlert]).value!
        assert GitHub.newsies.subscribe_to_thread_types(@explicit_access_read_user, @repo, [SecurityAlert]).value!
        assert GitHub.newsies.subscribe_to_thread_types(@explicit_access_write_user, @repo, [SecurityAlert]).value!

        GitHub.newsies.get_and_update_settings(@owner) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@member) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@repo_admin) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@explicit_access_read_user) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@explicit_access_write_user) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end

        assert_equal [
          {
            reason: "security_alert",
            users: [@owner, @member, @repo_admin, @explicit_access_read_user, @explicit_access_write_user],
          },
        ], @adapter.explicit_recipients
      end

      test "returns mixed users that are watching parts of the repository" do
        assert @owner.watch_repo(@repo, enqueue: false)
        assert GitHub.newsies.subscribe_to_thread_types(@member, @repo, [SecurityAlert]).value!
        assert @repo_admin.watch_repo(@repo, enqueue: false)
        assert GitHub.newsies.subscribe_to_thread_types(@explicit_access_write_user, @repo, [SecurityAlert]).value!

        GitHub.newsies.get_and_update_settings(@owner) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@member) do |setting|
          setting.subscribed_settings.delete(Newsies::HANDLER_EMAIL)
        end
        GitHub.newsies.get_and_update_settings(@repo_admin) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@explicit_access_read_user) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end
        GitHub.newsies.get_and_update_settings(@explicit_access_write_user) do |setting|
          setting.subscribed_settings << Newsies::HANDLER_EMAIL
        end

        assert_equal [
          {
            reason: "security_alert",
            users: [@owner, @repo_admin, @explicit_access_write_user],
          },
        ], @adapter.explicit_recipients
      end
    end

    context "#attributes" do
      test "is nil" do
        assert_nil @adapter.attributes
      end
    end

    context "#owner_id" do
      test "returns the repository owner ID" do
        assert_equal @repo.owner_id, @adapter.owner_id
      end
    end

    context "#owner_type" do
      test "returns the repository owner type for an organization" do
        assert_equal :organization, @adapter.owner_type
      end

      test "returns the repository owner type for a user" do
        repo = create(:private_repository, owner: @owner, from_example: :simple)
        campaign_repository = create(:security_campaign_repository, repository: repo, security_campaign: @campaign)

        assert_equal :user, Notifyd::SecurityCampaignRepositoryAdapter.new(campaign_repository).owner_type
      end
    end

    context "#trigger" do
      test "returns the operation from the context for create" do
        adapter = Notifyd::SecurityCampaignRepositoryAdapter.new(@campaign_repository, {
          operation: "create",
        })

        assert_equal "create", adapter.trigger
      end

      test "returns the operation from the context for close" do
        adapter = Notifyd::SecurityCampaignRepositoryAdapter.new(@campaign_repository, {
          operation: "close",
        })

        assert_equal "close", adapter.trigger
      end
    end
  end
end
