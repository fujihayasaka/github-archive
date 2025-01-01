# typed: true
# frozen_string_literal: true

require "test_helper"

class SubscriptionsMaintenanceTest < GitHub::TestCase
  context "#async_delete_list_subscriptions" do
    test "only deletes list subscriptions in Newsies for enterprise", enterprise_only: true, feature_enabled: :notifyd_maintenance_delete_repository do
      repo = create(:repository)
      repo_subject = Notifications::Subject.new(type: "Repository", id: repo.id)
      newsies_repo = Newsies::List.to_object(repo)

      GitHub.newsies.expects(:async_delete_all_for_list).with(newsies_repo)
      Notifyd::MaintenanceService.any_instance.expects(:delete_repository).never

      Notifications::Subscriptions.async_delete_list_subscriptions(repo_subject)
    end

    test "only deletes list subscriptions in Newsies for teams", skip_if_feature_disabled: :notifyd_maintenance_delete_repository do
      team = create(:team)
      team_subject = Notifications::Subject.new(type: "Team", id: team.id)
      newsies_team = Newsies::List.to_object(team)

      GitHub.newsies.expects(:async_delete_all_for_list).with(newsies_team)
      Notifyd::MaintenanceService.any_instance.expects(:delete_repository).never

      Notifications::Subscriptions.async_delete_list_subscriptions(team_subject)
    end

    test "only deletes list subscriptions in Newsies when feature flag is disabled", skip_if_feature_enabled: :notifyd_maintenance_delete_repository do
      repo = create(:repository)
      repo_subject = Notifications::Subject.new(type: "Repository", id: repo.id)
      newsies_repo = Newsies::List.to_object(repo)

      GitHub.newsies.expects(:async_delete_all_for_list).with(newsies_repo)
      Notifyd::MaintenanceService.any_instance.expects(:delete_repository).never

      Notifications::Subscriptions.async_delete_list_subscriptions(repo_subject)
    end

    test "delete list subscriptions in both Newsies and Notifyd when feature flag is enabled and list is a repository", skip_if_feature_disabled: :notifyd_maintenance_delete_repository do
      repo = create(:repository)
      repo_subject = Notifications::Subject.new(type: "Repository", id: repo.id)
      newsies_repo = Newsies::List.to_object(repo)

      GitHub.newsies.expects(:async_delete_all_for_list).with(newsies_repo)
      Notifyd::MaintenanceService.any_instance.expects(:delete_repository).with(repo.id)

      Notifications::Subscriptions.async_delete_list_subscriptions(repo_subject)
    end
  end

  context "#async_delete_list_subscriptions_for_users" do
    test "only deletes list subscriptions in Newsies for enterprise", enterprise_only: true, feature_enabled: :notifyd_maintenance_delete_repository_for_users do
      repo = create(:repository)
      repo_subject = Notifications::Subject.new(type: "Repository", id: repo.id)
      newsies_repo = Newsies::List.to_object(repo)
      user1 = create(:user)
      user2 = create(:user)
      user_ids = [user1.id, user2.id]

      GitHub.newsies.expects(:async_delete_all_for_list_and_users).with(newsies_repo, user_ids)
      Notifyd::MaintenanceService.any_instance.expects(:delete_repository_for_users).never

      Notifications::Subscriptions.async_delete_list_subscriptions_for_users(list: repo_subject, user_ids: user_ids)
    end

    test "only deletes list subscriptions in Newsies for teams", skip_if_feature_disabled: :notifyd_maintenance_delete_repository_for_users do
      team = create(:team)
      team_subject = Notifications::Subject.new(type: "Team", id: team.id)
      newsies_team = Newsies::List.to_object(team)
      user1 = create(:user)
      user2 = create(:user)
      user_ids = [user1.id, user2.id]

      GitHub.newsies.expects(:async_delete_all_for_list_and_users).with(newsies_team, user_ids)
      Notifyd::MaintenanceService.any_instance.expects(:delete_repository_for_users).never

      Notifications::Subscriptions.async_delete_list_subscriptions_for_users(list: team_subject, user_ids: user_ids)
    end

    test "only deletes list subscriptions in Newsies when feature flag is disabled", skip_if_feature_enabled: :notifyd_maintenance_delete_repository_for_users do
      repo = create(:repository)
      repo_subject = Notifications::Subject.new(type: "Repository", id: repo.id)
      newsies_repo = Newsies::List.to_object(repo)
      user1 = create(:user)
      user2 = create(:user)
      user_ids = [user1.id, user2.id]

      GitHub.newsies.expects(:async_delete_all_for_list_and_users).with(newsies_repo, user_ids)
      Notifyd::MaintenanceService.any_instance.expects(:delete_repository_for_users).never

      Notifications::Subscriptions.async_delete_list_subscriptions_for_users(list: repo_subject, user_ids: user_ids)
    end

    test "delete list subscriptions in both Newsies and Notifyd when feature flag is enabled and list is a repository", skip_if_feature_disabled: :notifyd_maintenance_delete_repository_for_users do
      repo = create(:repository)
      repo_subject = Notifications::Subject.new(type: "Repository", id: repo.id)
      newsies_repo = Newsies::List.to_object(repo)
      user1 = create(:user)
      user2 = create(:user)
      user_ids = [user1.id, user2.id]

      GitHub.newsies.expects(:async_delete_all_for_list_and_users).with(newsies_repo, user_ids)
      Notifyd::MaintenanceService.any_instance.expects(:delete_repository).with(repo_id: repo.id, user_ids: user_ids)

      Notifications::Subscriptions.async_delete_list_subscriptions_for_users(list: repo_subject, user_ids: user_ids)
    end
  end

  context "#async_delete_user_subscriptions" do
    test "only deletes user subscriptions in Newsies for enterprise", enterprise_only: true, feature_enabled: :notifyd_maintenance_delete_user do
      user = create(:user)

      GitHub.newsies.expects(:async_delete_all_for_user).with(user.id)
      Notifyd::MaintenanceService.any_instance.expects(:delete_user).never

      Notifications::Subscriptions.async_delete_user_subscriptions(user.id)
    end

    test "only deletes user subscriptions in Newsies when feature flag is disabled", skip_if_feature_enabled: :notifyd_maintenance_delete_repository do
      user = create(:user)

      GitHub.newsies.expects(:async_delete_all_for_user).with(user.id)
      Notifyd::MaintenanceService.any_instance.expects(:delete_user).never

      Notifications::Subscriptions.async_delete_user_subscriptions(user.id)
    end

    test "delete user subscriptions in both Newsies and Notifyd when feature flag is enabled", skip_if_feature_disabled: :notifyd_maintenance_delete_repository do
      user = create(:user)

      GitHub.newsies.expects(:async_delete_all_for_user).with(user.id)
      Notifyd::MaintenanceService.any_instance.expects(:delete_user).with(user.id)

      Notifications::Subscriptions.async_delete_user_subscriptions(user.id)
    end
  end

  context "#async_delete_list_subscriptions_for_lists" do
    test "only deletes list subscriptions in Newsies for enterprise", enterprise_only: true, feature_enabled: :notifyd_maintenance_delete_repository do
      user = create(:user)
      repo = create(:repository)
      repo_subject = Notifications::Subject.new(type: "Repository", id: repo.id)
      newsies_repo = Newsies::List.to_object(repo)
      team = create(:team)
      team_subject = Notifications::Subject.new(type: "Team", id: team.id)
      newsies_team = Newsies::List.to_object(team)

      GitHub.newsies.expects(:async_delete_all_for_user_and_lists).with(user_id: user.id, lists: [newsies_repo, newsies_team])
      Notifyd::MaintenanceService.any_instance.expects(:delete_user_repositories).never

      Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: user.id, lists: [repo_subject, team_subject])
    end

    test "only deletes list subscriptions in Newsies for teams", skip_if_feature_disabled: :notifyd_maintenance_delete_repository do
      user = create(:user)
      team = create(:team)
      team_subject = Notifications::Subject.new(type: "Team", id: team.id)
      newsies_team = Newsies::List.to_object(team)

      GitHub.newsies.expects(:async_delete_all_for_user_and_lists).with(user_id: user.id, lists: [newsies_team])
      Notifyd::MaintenanceService.any_instance.expects(:delete_user_repositories).never

      Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: user.id, lists: [team_subject])
    end

    test "only deletes list subscriptions in Newsies when feature flag is disabled", skip_if_feature_enabled: :notifyd_maintenance_delete_repository do
      user = create(:user)
      repo = create(:repository)
      repo_subject = Notifications::Subject.new(type: "Repository", id: repo.id)
      newsies_repo = Newsies::List.to_object(repo)
      team = create(:team)
      team_subject = Notifications::Subject.new(type: "Team", id: team.id)
      newsies_team = Newsies::List.to_object(team)

      GitHub.newsies.expects(:async_delete_all_for_user_and_lists).with(user_id: user.id, lists: [newsies_repo, newsies_team])
      Notifyd::MaintenanceService.any_instance.expects(:delete_user_repositories).never

      Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: user.id, lists: [repo_subject, team_subject])
    end

    test "delete list subscriptions in both Newsies and Notifyd when feature flag is enabled and list is a repository", skip_if_feature_disabled: :notifyd_maintenance_delete_repository do
      user = create(:user)
      repo = create(:repository)
      repo_subject = Notifications::Subject.new(type: "Repository", id: repo.id)
      newsies_repo = Newsies::List.to_object(repo)
      team = create(:team)
      team_subject = Notifications::Subject.new(type: "Team", id: team.id)
      newsies_team = Newsies::List.to_object(team)

      GitHub.newsies.expects(:async_delete_all_for_user_and_lists).with(user_id: user.id, lists: [newsies_repo, newsies_team])
      Notifyd::MaintenanceService.any_instance.expects(:delete_user_repositories).with(user_id: user.id, repo_ids: [repo.id])

      Notifications::Subscriptions.async_delete_user_subscriptions_for_lists(user_id: user.id, lists: [repo_subject, team_subject])
    end
  end
end
