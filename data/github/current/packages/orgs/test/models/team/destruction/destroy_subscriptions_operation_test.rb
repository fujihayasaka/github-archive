# typed: true
# frozen_string_literal: true
require "test_helper"

class TeamDestructionDestroySubscriptionsOperationTest < GitHub::TestCase
  fixtures do
    @parent_team = create(:team, privacy: :closed)
    @child_team = create(:team,
      organization: @parent_team.organization,
      parent_team_id: @parent_team.id,
      privacy: :closed)
    @other_team = create(:team, organization: @parent_team.organization)
    @teams = [@parent_team, @child_team, @other_team]
    @users = 2.times.map { create(:user) }
    @users.each do |user|
      @parent_team.organization.add_member(user)
      GitHub.newsies.get_and_update_settings(user) { |u| u.subscribed_settings.replace %w(web) }
    end
  end

  test "unsubscribes the users from the teams if they are not a member" do
    user_team_pairs = @users.product(@teams)
    user_team_pairs.each { |user, team| GitHub.newsies.subscribe_to_list(user, team) }
    user_team_pairs.each do |(user, team)|
      subscription = GitHub.newsies.subscription_status(user, team)
      assert subscription.valid? && subscription.subscribed?
    end

    only = [Newsies::DeleteAllForUserAndListsJob]
    perform_enqueued_jobs(only: only) do
      Team::Destruction::DestroySubscriptionsOperation
        .new(@users.map(&:id), @teams.map(&:id))
        .execute
    end

    user_team_pairs.each do |(user, team)|
      subscription = GitHub.newsies.subscription_status(user, team)
      refute subscription.subscribed?
    end
  end

  test "removes stale notifications along with removed subscriptions" do
    user_team_pairs = @users.product(@teams)
    user_team_pairs.each { |user, team| GitHub.newsies.subscribe_to_list(user, team) }
    assert_performed_with(job: SubscribeAndNotifyJob) do
      @teams.each { |t| create(:discussion_post, team: t) }
    end

    @users.each do |user|
      count = GitHub.newsies.web.count(user)
      assert count > 0, count
    end

    perform_enqueued_jobs(only: [Newsies::DeleteAllForUserAndListsJob]) do
      Team::Destruction::DestroySubscriptionsOperation
        .new(@users.map(&:id), @teams.map(&:id))
        .execute
    end

    @users.each { |user| assert_equal 0, GitHub.newsies.web.count(user) }
  end

  test "keeps subscriptions of direct members" do
    @parent_team.add_member(@users.first)
    subscription = GitHub.newsies.subscription_status(@users.first, @parent_team)
    assert subscription.valid? && subscription.subscribed?

    Team::Destruction::DestroySubscriptionsOperation
      .new([@users.first.id], [@parent_team.id])
      .execute

    subscription = GitHub.newsies.subscription_status(@users.first, @parent_team)
    assert subscription.valid? && subscription.subscribed?
  end

  test "keeps subscriptions of indirect members" do
    @child_team.add_member(@users.first)
    subscription = GitHub.newsies.subscription_status(@users.first, @parent_team)
    assert subscription.valid? && subscription.subscribed?

    Team::Destruction::DestroySubscriptionsOperation
      .new([@users.first.id], [@parent_team.id])
      .execute

    subscription = GitHub.newsies.subscription_status(@users.first, @parent_team)
    assert subscription.valid? && subscription.subscribed?
  end
end
