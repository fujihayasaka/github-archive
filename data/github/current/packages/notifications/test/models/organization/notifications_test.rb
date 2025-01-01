# typed: true
# frozen_string_literal: true
require "test_helper"

class OrganizationNotificationsTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @owner = create(:paid_user)
    @org = create(:organization, admin: @owner)
    only = [RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
    perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:none, actor: @owner) }

    @repo = create(:private_repository, owner: @org)
    @team = create(:team, organization: @org)
    @team.add_repository(@repo, :pull)
    @user = create(:user)

    enable_notifications_for_user(@user, enabled_handlers: ["web"])
  end

  setup do
    GitHub.flipper[:notifyd_issue_watch_activity_notify].disable
  end

  test "cleans up notifications when user is removed from an individual repo" do
    individual_repo = create(:private_repository, owner: @owner)
    refute individual_repo.readable_by?(@user), "User should not be able to read repo."
    individual_repo.add_member(@user)
    assert individual_repo.readable_by?(@user), "User should be able to read repo."
    @user.watch_repo(individual_repo)

    assert_difference -> { GitHub.newsies.web.count(@user) }, 1 do
      assert_performed_with job: SubscribeAndNotifyJob do
        create(:issue, repository: individual_repo)
      end
    end

    assert_difference -> { GitHub.newsies.web.count(@user) }, -1 do
      only = [Newsies::DeleteAllForUserAndListsJob, RemoveUserFromRepoCleanupJob]
      perform_enqueued_jobs(only: only) do
        individual_repo.remove_member(@user)
      end
    end

    refute individual_repo.readable_by?(@user), "User should not be able to read repo."
  end

  test "cleans up notifications when user loses admin access to private org repo" do
    public_repo = create(:public_repository, owner: @org)
    assert public_repo.readable_by?(@user), "User should be able to read repo."
    @user.watch_repo(public_repo)
    assert GitHub.newsies.subscription_status(@user, public_repo).valid?, "User's subscription should be valid."

    individual_repo = create(:private_repository, owner: @owner)
    refute individual_repo.readable_by?(@user), "User should not be able to read repo."
    individual_repo.add_member(@user)
    assert individual_repo.readable_by?(@user), "User not be able to read repo."
    @user.watch_repo(individual_repo)
    assert GitHub.newsies.subscription_status(@user, individual_repo).valid?, "User's subscription should be valid."

    refute @repo.readable_by?(@user), "User should not be able to read repo."
    @org.add_member(@user, adder: @owner)
    refute @repo.readable_by?(@user), "User should not be able to read repo."
    @org.update_member(@user, action: :admin)
    assert @repo.readable_by?(@user), "User should be able to read repo."
    @user.watch_repo(@repo)
    assert GitHub.newsies.subscription_status(@user, @repo).valid?, "User's subscription should be valid."

    assert_difference -> { GitHub.newsies.web.count(@user) }, 3 do
      assert_performed_with job: SubscribeAndNotifyJob do
        private_individual_issue = create(:issue, repository: individual_repo)
      end

      assert_performed_with job: SubscribeAndNotifyJob do
        public_issue = create(:issue, repository: public_repo)
      end

      assert_performed_with job: SubscribeAndNotifyJob do
        only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
        issue = perform_enqueued_jobs(only: only) { create(:issue, repository: @repo) }
      end
    end

    assert_difference -> { GitHub.newsies.web.count(@user) }, -1 do
      only = [CleanupListNotificationsJob, Newsies::DeleteAllForUserAndListsJob]
      perform_enqueued_jobs(only: only) { @org.update_member(@user, action: :read) }
    end

    refute @repo.readable_by?(@user), "User should not be able to read repo."
    refute GitHub.newsies.subscription_status(@user, @repo).valid?, "User's subscription should not be valid."

    assert public_repo.readable_by?(@user), "User should be able to read repo."
    assert GitHub.newsies.subscription_status(@user, public_repo).valid?, "User's subscription should be valid."
    assert individual_repo.readable_by?(@user), "User should be able to read repo."
    assert GitHub.newsies.subscription_status(@user, individual_repo).valid?, "User's subscription should be valid."
  end

  test "cleans up notification subscriptions in private org repos when user is removed from org" do
    public_repo = create(:public_repository, owner: @org)
    assert public_repo.readable_by?(@user), "User should be able to read repo."

    refute @repo.readable_by?(@user), "User should not be able to read repo."
    @org.add_member(@user, adder: @owner)
    refute @repo.readable_by?(@user), "User should not be able to read repo."
    @org.update_member(@user, action: :admin)
    assert @repo.readable_by?(@user), "User should be able to read repo."

    perform_enqueued_jobs(only:  [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]) do
      create(:issue, user: @user, repository: public_repo)
      create(:issue, user: @user, repository: @repo)
    end

    assert_equal Newsies::ThreadSubscription.where(list_id: @repo.id).count, 1
    assert_equal Newsies::ThreadSubscription.where(list_id: public_repo.id).count, 1

    only = [RevokeOrgMembershipAbilitiesJob, RemoveOrgMemberWatchedRepositoriesJob, BulkRemoveOrgMemberWatchedRepositoriesJob, Newsies::DeleteAllForUserAndListsJob]
    perform_enqueued_jobs(only: only) { @org.remove_member!(@user) }

    if GitHub.flipper[:notifications_cleanup_threads_on_member_change].enabled?
      assert_equal Newsies::ThreadSubscription.where(list_id: @repo.id).count, 0
      assert_equal Newsies::ThreadSubscription.where(list_id: public_repo.id).count, 1
    else
      assert_equal Newsies::ThreadSubscription.where(list_id: @repo.id).count, 1
      assert_equal Newsies::ThreadSubscription.where(list_id: public_repo.id).count, 1
    end
  end
end
