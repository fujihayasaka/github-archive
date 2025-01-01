# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsNewsiesTest < GitHub::TestCase
  fixtures do
    @user1 = create(:user)
    @user2 = create(:user)
    @repo = create(:repository)

    GitHub.newsies.get_and_update_settings(@user1) do |settings|
      settings.auto_subscribe_teams = true
    end

    GitHub.newsies.get_and_update_settings(@user2) do |settings|
      settings.auto_subscribe_teams = true
    end

    Team.where(id: @repo.id).destroy_all
    @team = create(:team, id: @repo.id)
    @team.add_member(@user2)
    @team.add_member(@user1)
    GitHub.newsies.ignore_list(@user1, @team)

    @user1.watch_repo @repo
    @user2.ignore_repo @repo

    @issue = create :issue, :subscribed_author, repository: @repo, user: @user1
    GitHub.newsies.ignore_thread(@user2, @repo, @issue)
  end

  context ".users_watching_repository" do
    test "finds watchers" do
      watchers = Stafftools::Newsies.users_watching_repository @repo
      assert_includes watchers, @user1
      refute_includes watchers, @user2
    end
  end

  context ".users_ignoring_repository" do
    test "finds ignorers" do
      ignorants = Stafftools::Newsies.users_ignoring_repository @repo
      assert_includes ignorants, @user2
      refute_includes ignorants, @user1
    end
  end

  context ".subscriptions_for_issue" do
    test "finds subscriptions" do
      subs = Stafftools::Newsies.subscriptions_for_issue @issue
      users = subs.map(&:user)
      assert_includes users, @user1
      refute_includes users, @user2
    end
  end

  context ".users_ignoring_issue" do
    test "finds ignorers" do
      ignorants = Stafftools::Newsies.users_ignoring_issue @issue
      assert_includes ignorants, @user2
      refute_includes ignorants, @user1
    end
  end
end
