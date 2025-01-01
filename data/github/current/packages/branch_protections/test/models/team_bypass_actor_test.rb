# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamBypassActorTest < GitHub::TestCase
  fixtures do
    @business_owner = create(:user)
    @business = create(:business, owners: [@business_owner])

    @org = create(:business_plus_organization, business: @business)
    @org_repo = create(:repository, owner: @org)
    @team1 = create(:team, organization: @org, name: "team 1", privacy: "closed")
    @team2 = create(:team, organization: @org, name: "team 2", privacy: "secret")
    @team3 = create(:team, organization: @org, name: "team 3", privacy: "closed")

    @user1 = create(:user)
    @team1.add_member(@user1)

    @user2 = create(:user)
    @team2.add_member(@user2)

    @ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @org)
  end

  test "create via type" do
    bypasser = RepositoryRulesetBypassActor.create(type: "TeamBypassActor", actor: @team1, repository_ruleset: @ruleset)
    assert bypasser.is_a?(TeamBypassActor)
    assert_predicate bypasser, :valid?
    assert_equal "Team", bypasser.actor_type
    assert_equal "TeamBypassActor", bypasser.type
    bypasser.save!
  end

  test "create bypass actor" do
    actor = TeamBypassActor.create(actor: @team1, repository_ruleset: @ruleset)

    assert_equal @team1.id, actor.actor_id
    assert actor.valid?
    assert_equal "Team", actor.actor_type
    assert_equal "TeamBypassActor", actor.type
  end

  test "suggest and validate" do
    bypassers = TeamBypassActor.suggest_bypassers(@org, @org.admins.first, nil)
    assert_equal 2, bypassers.size # should omit the secret team
    assert_same_elements [@team1.id, @team3.id], bypassers.map(&:actor_id)
    assert_same_elements ["team 1", "team 3"], bypassers.map(&:actor_name)
    assert_same_elements [@team1, @team3], bypassers.map(&:actor)

    bypasser = T.must(bypassers.first)
    assert_equal TeamBypassActor, bypasser.class
    assert_equal "Team", bypasser.class.display_type
    assert_equal "Team", bypasser.class.display_name

    bypasser.repository_ruleset = @ruleset
    assert bypasser.valid?
    bypasser.save!
  end

  test "allowed_bypass_modes" do
    @ruleset.bypass_actors << TeamBypassActor.new(actor: @team1, bypass_mode: 0)
    @ruleset.save!
    rando = create(:user)
    repo_user = create(:user)
    @org_repo.add_member(repo_user, action: :admin)

    assert_equal [], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, rando, @org_repo)
    assert_equal [], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_user, @org_repo)
    assert_equal [], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user2, @org_repo)
    assert_equal [0], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user1, @org_repo)

    @ruleset.bypass_actors.first.bypass_mode = 1
    @ruleset.bypass_actors.first.save!
    @ruleset.bypass_actors << TeamBypassActor.new(actor: @team2, bypass_mode: 0)

    assert_equal [], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, rando, @org_repo)
    assert_equal [], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_user, @org_repo)
    assert_equal [0], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user2, @org_repo)
    assert_equal [1], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user1, @org_repo)

    @team1.add_member(@user2)
    assert_same_elements [0, 1], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user2, @org_repo)
    assert_equal [1], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user1, @org_repo)

    @team1.remove_member(@user1)
    assert_equal [], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user1, @org_repo)
  end

  test "deleted team does not raise" do
    assert_equal [], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user1, @org_repo)
    bypasser = TeamBypassActor.new(actor: @team1, bypass_mode: 0)
    @ruleset.bypass_actors << bypasser
    @ruleset.save!
    assert_equal [0], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user1, @org_repo)
    assert_same_elements [@user1.id], TeamBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)
    @team1.destroy
    perform_enqueued_jobs(only: DestroyTeamDependantsJob)
    @ruleset.reload
    bypasser.reload
    assert_nil bypasser.actor_name
    assert_nil bypasser.actor_owner_name
    assert_equal [], TeamBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @user1, @org_repo)
    assert_equal [], TeamBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)
  end

  test "bypassable_user_ids" do
    @ruleset.bypass_actors << TeamBypassActor.new(actor: @team1, bypass_mode: 0)
    @ruleset.save!

    assert_same_elements [@user1.id], TeamBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)

    @ruleset.bypass_actors << TeamBypassActor.new(actor: @team2, bypass_mode: 0)
    assert_same_elements [@user1.id, @user2.id], TeamBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)

    @team1.remove_member(@user1)
    assert_same_elements [@user2.id], TeamBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)
  end

  test "missing team does not raise" do
    @ruleset.bypass_actors << TeamBypassActor.new(actor: @team1, bypass_mode: 0)
    @ruleset.save!

    refute_nil @ruleset.bypass_actors.first.actor_name
    refute_nil @ruleset.bypass_actors.first.actor_preferred_avatar_url

    @team1.destroy
    assert_nil @ruleset.reload.bypass_actors.first.actor_name
    assert_nil @ruleset.bypass_actors.first.actor_preferred_avatar_url
  end
end
