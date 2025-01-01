# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamBypassActorTest < GitHub::TestCase
  fixtures do
    @business_owner = create(:user)
    @business = create(:business, owners: [@business_owner])

    @org = create(:business_plus_organization, business: @business)
    @org_repo = create(:repository, owner: @org)
    @enterprise_team1 = create(:enterprise_team, business: @business, name: "team 1")
    @enterprise_team2 = create(:enterprise_team, business: @business, name: "team 2")

    @ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @business)
  end

  setup do
    enable_feature_flag(:enterprise_teams_enabled_for_organizations)
    enable_feature_flag(:enterprise_rulesets)
    enable_feature_flag(:enterprise_rulesets_enterprise_teams)
  end

  test "create via type" do
    bypasser = RepositoryRulesetBypassActor.create(type: "EnterpriseTeamBypassActor", actor: @enterprise_team1, repository_ruleset: @ruleset)
    assert bypasser.is_a?(EnterpriseTeamBypassActor)
    assert_predicate bypasser, :valid?
    assert_equal "EnterpriseTeam", bypasser.actor_type
    assert_equal "EnterpriseTeamBypassActor", bypasser.type
    bypasser.save!
  end

  test "create bypass actor" do
    ruleset = create(:repository_ruleset, :targets_all_orgs, source: @business, target: "repository")

    actor = EnterpriseTeamBypassActor.create(actor: @enterprise_team1, repository_ruleset: ruleset)

    assert_equal @enterprise_team1.id, actor.actor_id
    assert_predicate actor, :valid?
    assert_equal "EnterpriseTeam", actor.actor_type
    assert_equal "EnterpriseTeamBypassActor", actor.type
  end

  test "missing team does not raise" do
    @ruleset.bypass_actors << EnterpriseTeamBypassActor.create(actor: @enterprise_team1, repository_ruleset: @ruleset)
    @ruleset.save!

    refute_nil @ruleset.reload.bypass_actors.first.actor_name

    @enterprise_team1.destroy
    assert_nil @ruleset.reload.bypass_actors.first.actor_name
    assert_nil @ruleset.bypass_actors.first.actor_preferred_avatar_url
  end

  # this won't work until we can get business.enterprise_teams_enabled? to return true
  # test "suggest and validate" do
  #   bypassers = EnterpriseTeamBypassActor.suggest_bypassers(@business, nil)
  #   assert_equal 2, bypassers.size
  #   bypasser = T.must(bypassers.first)
  #   assert_equal EnterpriseTeamBypassActor, bypasser.class
  #   assert_equal "EnterpriseTeam", bypasser.class.display_type
  #   assert_equal "Enterprise teams", bypasser.class.display_name

  #   assert_equal @enterprise_team1, bypasser.actor
  #   assert_equal "team 1", bypasser.actor_name
  #   assert_equal "EnterpriseTeamBypassActor", bypasser.type

  #   bypasser.repository_ruleset = @ruleset
  #   assert bypasser.valid?
  #   bypasser.save!
  #
  #   TODO: destroy the team and verify the methods don't raise exceptions
  # end
end
