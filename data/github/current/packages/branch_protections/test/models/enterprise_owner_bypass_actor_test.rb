# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseOwnerBypassActorTest < GitHub::TestCase
  fixtures do
    @business_owner = create(:user)
    @business = create(:business, owners: [@business_owner])

    @org = create(:business_plus_organization, business: @business)
    @org_repo = create(:repository, owner: @org)
    @ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @org)
  end

  test "create via type" do
    bypasser = RepositoryRulesetBypassActor.create(type: "EnterpriseOwnerBypassActor", repository_ruleset: @ruleset)
    assert bypasser.is_a?(EnterpriseOwnerBypassActor)
    assert_predicate bypasser, :valid?
    assert_equal "EnterpriseOwner", bypasser.actor_type
    assert_equal "EnterpriseOwnerBypassActor", bypasser.type
    bypasser.save!
  end

  test "create bypass actor" do
    ruleset = create(:repository_ruleset, :targets_all_orgs, source: @business, target: "repository")

    bypasser = EnterpriseOwnerBypassActor.create(repository_ruleset: ruleset)
    assert_predicate bypasser, :valid?
    assert_equal "EnterpriseOwner", bypasser.actor_type
    assert_nil bypasser.actor_id
    assert_equal "EnterpriseOwnerBypassActor", bypasser.type
  end

  test "suggest and validate" do
    bypassers = EnterpriseOwnerBypassActor.suggest_bypassers(@org_repo, nil)
    assert_equal 1, bypassers.size
    bypasser = T.must(bypassers.first)
    assert_equal EnterpriseOwnerBypassActor, bypasser.class
    assert_equal "EnterpriseOwner", bypasser.class.display_type
    assert_equal "Enterprise owners", bypasser.class.display_name

    assert_nil bypasser.actor
    assert_equal "Enterprise owners", bypasser.actor_name
    assert_equal "EnterpriseOwnerBypassActor", bypasser.type

    bypasser.repository_ruleset = @ruleset
    assert bypasser.valid?
    bypasser.save!
  end

  test "allowed_bypass_modes" do
    @ruleset.bypass_actors << EnterpriseOwnerBypassActor.new(bypass_mode: 0)
    @ruleset.save!

    rando = create(:user)
    repo_user = create(:user)
    @org_repo.add_member(repo_user, action: :admin)

    assert_equal [], EnterpriseOwnerBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, rando, @org_repo)
    assert_equal [], EnterpriseOwnerBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_user, @org_repo)
    assert_equal [], EnterpriseOwnerBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @org.admins.first, @org_repo)
    assert_equal [0], EnterpriseOwnerBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @business_owner, @org_repo)

    @ruleset.bypass_actors.first.bypass_mode = 1
    @ruleset.bypass_actors.first.save!
    assert_equal [], EnterpriseOwnerBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, rando, @org_repo)
    assert_equal [], EnterpriseOwnerBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_user, @org_repo)
    assert_equal [], EnterpriseOwnerBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @org.admins.first, @org_repo)
    assert_equal [1], EnterpriseOwnerBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @business_owner, @org_repo)
  end

  test "only one per ruleset" do
    @ruleset.bypass_actors << EnterpriseOwnerBypassActor.new(bypass_mode: 0)
    assert @ruleset.valid?

    @ruleset.bypass_actors << EnterpriseOwnerBypassActor.new(bypass_mode: 0)
    refute @ruleset.valid?
  end

  test "bypassable_user_ids" do
    @ruleset.bypass_actors << EnterpriseOwnerBypassActor.new(bypass_mode: 0)
    @ruleset.save!

    expected_ids = @business.owners.map(&:id)
    assert_same_elements expected_ids, EnterpriseOwnerBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)

    owner2 = create(:user)
    @business.add_owner(owner2, actor: @business_owner)
    expected_ids << owner2.id
    assert_same_elements expected_ids, EnterpriseOwnerBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)
  end
end
