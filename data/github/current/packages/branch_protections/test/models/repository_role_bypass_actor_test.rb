# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRoleBypassActorTest < GitHub::TestCase

  fixtures do
    @business_owner = create(:user)
    @business = create(:business, owners: [@business_owner])
    @org_admin = create(:user)
    @org = create(:business_plus_organization, business: @business, admin: @org_admin)
    @org_repo = create(:repository, owner: @org)
    @ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: @ruleset)

    @rando = create(:user, name: "rando")
    @admin_user = create(:user, name: "admin-user")
    @org_repo.add_member(@admin_user, action: :admin)
    @write_user = create(:user, name: "write")
    @org_repo.add_member(@write_user, action: :write)
    @maintain_user = create(:user, name: "maintain")
    @org_repo.add_member(@maintain_user, action: :maintain)
    @read_user = create(:user, name: "read")
    @org_repo.add_member(@read_user, action: :read)
  end

  test "create via type" do
    bypasser = RepositoryRulesetBypassActor.create(type: "RepositoryRoleBypassActor", actor: RepositoryRole.admin_role, repository_ruleset: @ruleset)
    assert bypasser.is_a?(RepositoryRoleBypassActor)
    assert_predicate bypasser, :valid?
    assert_equal bypasser.actor_type, "RepositoryRole"
    assert_equal "RepositoryRoleBypassActor", bypasser.type
    bypasser.save!
  end

  test "create bypass actor" do
    bypasser = RepositoryRoleBypassActor.create(actor: RepositoryRole.write_role, repository_ruleset: @ruleset)
    assert_equal RepositoryRole.write_role.id, bypasser.actor_id
    assert_equal "RepositoryRole", bypasser.actor_type
    assert_predicate bypasser, :valid?
    assert_equal bypasser.actor_type, "RepositoryRole"
    assert_equal bypasser.actor_name, "Write"
    assert_equal "RepositoryRoleBypassActor", bypasser.type
  end

  test "suggest and validate" do
    bypassers = RepositoryRoleBypassActor.suggest_bypassers(@org_repo, nil)
    assert_equal 3, bypassers.size
    assert_same_elements [RepositoryRole.write_role.id, RepositoryRole.admin_role.id, RepositoryRole.maintain_role.id], bypassers.map(&:actor_id)
    assert_same_elements ["Write", "Repository admin", "Maintain"], bypassers.map(&:actor_name)

    bypasser = T.must(bypassers.first)
    assert_equal RepositoryRoleBypassActor, bypasser.class
    assert_equal "RepositoryRole", bypasser.class.display_type
    assert_equal "Repository roles", bypasser.class.display_name
    assert_equal "RepositoryRoleBypassActor", bypasser.type

    bypasser.repository_ruleset = @ruleset
    assert bypasser.valid?
    bypasser.save!
  end

  test "allowed_bypass_modes" do
    @ruleset.bypass_actors << RepositoryRoleBypassActor.new(actor: RepositoryRole.write_role, bypass_mode: 0)
    @ruleset.bypass_actors << RepositoryRoleBypassActor.new(actor: RepositoryRole.admin_role, bypass_mode: 1)
    @ruleset.save!

    assert_equal [], RepositoryRoleBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @rando, @org_repo)
    assert_equal [], RepositoryRoleBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @read_user, @org_repo)
    assert_equal [0], RepositoryRoleBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @write_user, @org_repo)
    # maintainers have write role
    assert_equal [0], RepositoryRoleBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @maintain_user, @org_repo)
    # admins have write role and admin role
    assert_same_elements [0, 1], RepositoryRoleBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @admin_user, @org_repo)

    @ruleset.bypass_actors << RepositoryRoleBypassActor.new(actor: RepositoryRole.maintain_role, bypass_mode: 1)
    assert_same_elements [0, 1], RepositoryRoleBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, @maintain_user, @org_repo)
  end

  test "bypassable_user_ids" do
    assert_same_elements [], RepositoryRoleBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)

    @ruleset.bypass_actors << RepositoryRoleBypassActor.new(actor: RepositoryRole.admin_role, bypass_mode: 0)
    @ruleset.save!

    expected_ids = [@org_admin.id, @admin_user.id]
    assert_same_elements expected_ids, RepositoryRoleBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)

    @ruleset.bypass_actors << RepositoryRoleBypassActor.new(actor: RepositoryRole.maintain_role, bypass_mode: 1)
    expected_ids << @maintain_user.id
    assert_same_elements expected_ids, RepositoryRoleBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)

    @ruleset.bypass_actors << RepositoryRoleBypassActor.new(actor: RepositoryRole.write_role, bypass_mode: 0)
    expected_ids << @write_user.id
    assert_same_elements expected_ids, RepositoryRoleBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)
  end

  test "deleted role does not raise" do
    bob = create(:user)
    custom_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: RepositoryRole.write_role.id)
    team = create(:team, organization: @org, name: "team 1", privacy: "closed")
    team.add_member(bob)
    user_role = UserRole.create!(actor: team, target: @org_repo, role: custom_role)
    assert_equal [], RepositoryRoleBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, bob, @org_repo)

    bypasser = RepositoryRulesetBypassActor.create(type: "RepositoryRoleBypassActor", actor: custom_role, repository_ruleset: @ruleset)
    @ruleset.bypass_actors << bypasser
    @ruleset.save!

    assert_equal [0], RepositoryRoleBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, bob, @org_repo)
    assert_same_elements [bob.id], RepositoryRoleBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)

    custom_role.destroy

    @ruleset.reload
    bypasser.reload
    assert_nil bypasser.actor_name
    assert_nil bypasser.actor_owner_name
    assert_equal [], RepositoryRoleBypassActor.allowed_bypass_modes(@ruleset.bypass_actors.to_a, bob, @org_repo)
    assert_equal [], RepositoryRoleBypassActor.bypassable_user_ids(@org_repo, @ruleset.bypass_actors.to_a)
  end
end
