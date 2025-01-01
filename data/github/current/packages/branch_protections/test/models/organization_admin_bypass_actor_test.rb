# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationAdminBypassActorTest < GitHub::TestCase
  fixtures do
    @business_owner = create(:user)
    @business = create(:business, owners: [@business_owner])
    @org_admin = create(:user)
    @org = create(:business_plus_organization, business: @business, admin: @org_admin)
    @org_repo = create(:repository, owner: @org)
    @ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @org)
  end

  test "create via type" do
    bypasser = RepositoryRulesetBypassActor.create(type: "OrganizationAdminBypassActor", repository_ruleset: @ruleset)
    assert bypasser.is_a?(OrganizationAdminBypassActor)
    assert_predicate bypasser, :valid?
    assert_equal "OrganizationAdmin", bypasser.actor_type
    assert_equal "OrganizationAdminBypassActor", bypasser.type
    bypasser.save!
  end

  test "create bypass actor" do
    bypasser = OrganizationAdminBypassActor.create(repository_ruleset: @ruleset)
    assert_predicate bypasser, :valid?
    assert_equal "OrganizationAdmin", bypasser.actor_type
    assert_equal "OrganizationAdminBypassActor", bypasser.type
    bypasser.save!
  end

  test "suggest and validate" do
    bypassers = OrganizationAdminBypassActor.suggest_bypassers(@org_repo, nil)
    assert_equal 1, bypassers.size
    bypasser = T.must(bypassers.first)
    assert_equal OrganizationAdminBypassActor, bypasser.class
    assert_equal "OrganizationAdmin", bypasser.class.display_type
    assert_equal "Organization admin", bypasser.class.display_name

    assert_nil bypasser.actor
    assert_equal "Organization admin", bypasser.actor_name
    assert_equal "OrganizationAdminBypassActor", bypasser.type

    bypasser.repository_ruleset = @ruleset
    assert bypasser.valid?
    bypasser.save!
  end

  test "allowed_bypass_modes" do
    @ruleset.bypass_actors << OrganizationAdminBypassActor.new(bypass_mode: 0)
    @ruleset.save!
    rando = create(:user)
    repo_user = create(:user)
    @org_repo.add_member(repo_user, action: :admin)

    assert_equal [], OrganizationAdminBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, rando, @org_repo)
    assert_equal [], OrganizationAdminBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_user, @org_repo)
    assert_equal [0], OrganizationAdminBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @org.admins.first, @org_repo)

    @ruleset.bypass_actors.first.bypass_mode = 1
    @ruleset.bypass_actors.first.save!

    assert_equal [], OrganizationAdminBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, rando, @org_repo)
    assert_equal [], OrganizationAdminBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, repo_user, @org_repo)
    assert_equal [1], OrganizationAdminBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @org.admins.first, @org_repo)
  end

  test "only one per ruleset" do
    @ruleset.bypass_actors << OrganizationAdminBypassActor.new(bypass_mode: 0)
    assert @ruleset.valid?

    @ruleset.bypass_actors << OrganizationAdminBypassActor.new(bypass_mode: 0)
    refute @ruleset.valid?
  end

  test "bypassable_user_ids" do
    @ruleset.bypass_actors << OrganizationAdminBypassActor.new(bypass_mode: 0)
    @ruleset.save!

    expected_ids = @org.admins.map(&:id)
    assert_same_elements expected_ids, OrganizationAdminBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)

    admin2 = create(:user)
    @org.add_member(admin2, action: :admin)
    expected_ids << admin2.id
    assert_same_elements expected_ids, OrganizationAdminBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)
  end
end
