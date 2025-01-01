# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamParentChangeRecalculateSubscriptionsOperationTest < GitHub::TestCase

  fixtures do
    #                                              team
    #                                            /
    #                                 parent_team
    #                                /
    #              grand_parent_team
    #            /
    #  root_team                         new_parent_team
    #            \                     /
    #             new_grand_parent_team
    #
    #
    @root_team = create(:team, privacy: :closed)
    org = @root_team.organization
    @grand_parent_team = create(:team, organization: org, parent_team_id: @root_team.id, privacy: :closed)
    @parent_team = create(:team, organization: org, parent_team_id: @grand_parent_team.id, privacy: :closed)
    @team = create(:team, organization: org, parent_team_id: @parent_team.id, privacy: :closed)
    @new_grand_parent_team = create(:team, organization: org, parent_team_id: @root_team.id, privacy: :closed)
    @new_parent_team = create(:team, organization: org, parent_team_id: @new_grand_parent_team.id, privacy: :closed)
  end

  setup do
    @user = create(:user)
    @team.add_member(@user)
  end

  def move_to_new_parent_team
    tree_node = @team.tree_node
    new_node = tree_node.move_to(@new_parent_team.id)
    payload = Team::ParentChange::Payload.new(
      team_id: @team.id,
      old_path: @team.tree_node.path,
      new_path: new_node.path,
      old_descendants: tree_node.descendants,
    )

    Team::ParentChange::RecalculateSubscriptionsOperation.new(payload).execute
  end

  test "user is initially subscribed to the team and its parent teams" do
    assert_predicate GitHub.newsies.subscription_status(@user, @root_team), :subscribed?
    assert_predicate GitHub.newsies.subscription_status(@user, @grand_parent_team), :subscribed?
    assert_predicate GitHub.newsies.subscription_status(@user, @parent_team), :subscribed?
    assert_predicate GitHub.newsies.subscription_status(@user, @team), :subscribed?
    refute_predicate GitHub.newsies.subscription_status(@user, @new_grand_parent_team), :subscribed?
    refute_predicate GitHub.newsies.subscription_status(@user, @new_parent_team), :subscribed?
  end

  test "unsubscribes user from old parent teams" do
    move_to_new_parent_team

    refute_predicate GitHub.newsies.subscription_status(@user, @grand_parent_team), :subscribed?
    refute_predicate GitHub.newsies.subscription_status(@user, @parent_team), :subscribed?
  end

  test "does not unsubscribe from old parent teams when there is a direct membership" do
    another_user = create(:user)
    @team.add_member(another_user)
    @grand_parent_team.add_member(another_user)

    move_to_new_parent_team

    assert_predicate GitHub.newsies.subscription_status(another_user, @grand_parent_team), :subscribed?
    refute_predicate GitHub.newsies.subscription_status(another_user, @parent_team), :subscribed?
  end

  test "subscribes user to new parent teams" do
    move_to_new_parent_team

    assert_predicate GitHub.newsies.subscription_status(@user, @root_team), :subscribed?
    assert_predicate GitHub.newsies.subscription_status(@user, @team), :subscribed?
    assert_predicate GitHub.newsies.subscription_status(@user, @new_grand_parent_team), :subscribed?
    assert_predicate GitHub.newsies.subscription_status(@user, @new_parent_team), :subscribed?
  end
end
