# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryRulesetBypassActorTest < GitHub::TestCase
  include RepositoriesTestHelper
  include GpgKeyHelper

  fixtures do
    @user = create(:user)

    @org_member_1 = create(:user)
    @org_member_2 = create(:user)
    @org_member_3 = create(:user)

    @business_owner = create(:user)
    @business = create :business, owners: [@business_owner]

    @org = create(:business_plus_organization, business: @business)
    @org.add_member(@org_member_1)
    @org.add_member(@org_member_2)
    @org.add_member(@org_member_3)

    @team_1 = create(:team, organization: @org, privacy: :closed)
    @team_1.add_member(@org_member_1)
    @team_1.add_member(@org_member_2)

    @team_2 = create(:team, organization: @org, privacy: :closed)
    @team_2.add_member(@org_member_3)

    @org_repo = create(:repository, owner: @org)
    @org_repo.add_member(@org_member_1, action: :admin)
    @org_repo.add_member(@org_member_2, action: :write)
    @org_repo.add_team(@team_2, action: :admin)

    @ruleset = create(:repository_ruleset, :example_ruleset, name: "testing", source: @org)
  end

  test "upsert_bypass_actors supports strings or symbol keys" do
    assert RepositoryRulesetBypassActor.upsert_bypass_actors(@ruleset, [{ "actor_id": @team_1.id, actor_type: "Team", bypass_mode: 1 }, { actor_id: @team_2.id, actor_type: "Team", bypass_mode: "pull_request" }])
    assert_equal 2, @ruleset.bypass_actors.count
    assert_equal "TeamBypassActor", @ruleset.bypass_actors[0].type
    assert_equal 1, @ruleset.bypass_actors[0].bypass_mode
    assert_equal "TeamBypassActor", @ruleset.bypass_actors[1].type
    assert_equal 1, @ruleset.bypass_actors[1].bypass_mode
  end

  test "upsert_bypass_actors does not require optional actors" do
    assert RepositoryRulesetBypassActor.upsert_bypass_actors(@ruleset, [{ actor_id: nil, type: "OrganizationAdminBypassActor", bypass_mode: 0 }])
    assert_equal 1, @ruleset.bypass_actors.count
    assert_equal "OrganizationAdminBypassActor", @ruleset.bypass_actors.first.type
    assert_equal 0, @ruleset.bypass_actors.first.bypass_mode

    assert RepositoryRulesetBypassActor.upsert_bypass_actors(@ruleset, [{ actor_id: nil, actor_type: nil, type: "DeployKeyBypassActor" }])
    assert_equal 1, @ruleset.bypass_actors.count
    assert_equal "DeployKeyBypassActor", @ruleset.bypass_actors.first.type

    assert RepositoryRulesetBypassActor.upsert_bypass_actors(@ruleset, [{ type: "EnterpriseOwnerBypassActor" }])
    assert_equal 1, @ruleset.bypass_actors.count
    assert_equal "EnterpriseOwnerBypassActor", @ruleset.bypass_actors.first.type
  end

  test "upsert_bypass_actors ignores unknown fields" do
    assert RepositoryRulesetBypassActor.upsert_bypass_actors(@ruleset, [{ description: "hello", "whatever": "hi there", "type": "OrganizationAdminBypassActor" }])
    assert_equal 1, @ruleset.bypass_actors.count
    assert_equal "OrganizationAdminBypassActor", @ruleset.bypass_actors.first.type
  end

  test "upsert_bypass_actors should ignore duplicate additions" do
    # first try with no bypass actors
    RepositoryRulesetBypassActor.upsert_bypass_actors(@ruleset,
    [
      { actor_id: Role.write_role.id, actor_type: "RepositoryRole" },
      { actor_id: Role.write_role.id, actor_type: "RepositoryRole" }
    ])
    assert_equal 1, @ruleset.bypass_actors.count
    assert_equal "RepositoryRoleBypassActor", @ruleset.bypass_actors.first.type

    # now do it again now that one is already persisted
    RepositoryRulesetBypassActor.upsert_bypass_actors(@ruleset,
      [
        { actor_id: Role.write_role.id, actor_type: "RepositoryRole" },
        { actor_id: Role.write_role.id, actor_type: "RepositoryRole" }
      ])
    assert_equal 1, @ruleset.bypass_actors.count
    assert_equal "RepositoryRoleBypassActor", @ruleset.bypass_actors.first.type

    RepositoryRulesetBypassActor.upsert_bypass_actors(@ruleset,
    [
      { type: "OrganizationAdminBypassActor" },
      { type: "OrganizationAdminBypassActor", actor_id: 1, actor_type: "Sandwich" }
    ])
    assert_equal 1, @ruleset.bypass_actors.count
    assert_equal "OrganizationAdminBypassActor", @ruleset.bypass_actors.first.type
  end

  test "translate_bypass_actors supports strings or symbol keys" do
    hashes = RepositoryRulesetBypassActor.translate_bypass_actors(@ruleset, [{ "actor_id": @team_1.id, actor_type: "Team" }, { actor_id: @team_2.id, actor_type: "Team" }])
    assert_equal 2, hashes.count
    assert_equal @team_1.id, T.must(hashes[0])[:actor_id]
    assert_equal @team_2.id, T.must(hashes[1])[:actor_id]
  end

  test "translate_bypass_actors does not require optional actors" do
    hashes = RepositoryRulesetBypassActor.translate_bypass_actors(@ruleset, [{ actor_id: nil, type: "OrganizationAdminBypassActor" }])
    assert_equal 1, hashes.count
    assert_equal "OrganizationAdminBypassActor", T.must(hashes[0])[:type]

    hashes = RepositoryRulesetBypassActor.translate_bypass_actors(@ruleset, [{ actor_id: nil, actor_type: nil, type: "DeployKeyBypassActor" }])
    assert_equal 1, hashes.count
    assert_equal "DeployKeyBypassActor", T.must(hashes[0])[:type]

    hashes = RepositoryRulesetBypassActor.translate_bypass_actors(@ruleset, [{ type: "EnterpriseOwnerBypassActor" }])
    assert_equal 1, hashes.count
    assert_equal "EnterpriseOwnerBypassActor", T.must(hashes[0])[:type]
  end

  test "translate_bypass_actors allows unknown fields" do
    hashes = RepositoryRulesetBypassActor.translate_bypass_actors(@ruleset, [{ description: "hello", "whatever": "hi there", "type": "OrganizationAdminBypassActor" }])
    assert_equal 1, hashes.count
    assert_equal "OrganizationAdminBypassActor", T.must(hashes[0])[:type]
  end

  test "translate_bypass_actors requires a valid type" do
    assert_raises(ActiveRecord::SubclassNotFound) do
      RepositoryRulesetBypassActor.translate_bypass_actors(@ruleset, [{ "type": "Mystery" }])
    end

    assert_raises(RepositoryRuleset::Error) do
      RepositoryRulesetBypassActor.translate_bypass_actors(@ruleset, [{ "actor_type": "Mystery" }])
    end
  end

  test "Cannot exceed actor limit" do
    RepositoryRulesetBypassActor::ACTOR_LIMIT.times do
      team = create(:team, organization: @org, privacy: :closed)
      actor = RepositoryRulesetBypassActor.create(actor: team, repository_ruleset: @ruleset)
    end
    assert_equal @ruleset.bypass_actors.count, RepositoryRulesetBypassActor::ACTOR_LIMIT

    actor = RepositoryRulesetBypassActor.create(actor: @team_1, repository_ruleset: @ruleset)
    refute_predicate actor, :valid?
    assert_equal RepositoryRuleset::BypassActorsLimitError::MESSAGE, actor.errors.full_messages.first
  end

  test "User bypass actor is not valid" do
    actor = RepositoryRulesetBypassActor.create(
      actor: @user,
      repository_ruleset: @ruleset
    )

    assert_equal actor.actor_id, @user.id
    assert_equal actor.actor_type, "User"
    refute_predicate actor, :valid?
  end

  test "Team bypass actor is valid" do
    actor = RepositoryRulesetBypassActor.create(
      actor: @team_1,
      repository_ruleset: @ruleset
    )

    assert_equal actor.actor_id, @team_1.id
    assert_predicate actor, :valid?
    assert_equal actor.actor_type, "Team"
    assert_equal "TeamBypassActor", actor.type
  end

  test "Integration bypass actor is valid" do
    signing_key = create_gpg_key
    key_user = signing_key.user
    @org_repo.add_member(key_user, action: :write)
    bot = create(:integration, owner: key_user).bot
    make_integration_installation(integration: bot.integration, repository: @org_repo, permissions: { "contents" => :write })

    ruleset = create(:repository_ruleset, :targets_all_branches, source: @org_repo)
    create(:repository_rule_configuration, repository_ruleset: ruleset)

    actor = RepositoryRulesetBypassActor.create(
      actor: bot.integration,
      repository_ruleset: ruleset
    )

    assert_equal actor.actor_id, bot.integration.id
    assert_predicate actor, :valid?
    assert_equal actor.actor_type, "Integration"
    assert_equal "IntegrationBypassActor", actor.type
  end

  test "Enterprise Team bypass actor is valid" do
    enterprise_team = create(:enterprise_team, business: @business)
    ruleset = create(:repository_ruleset, :targets_all_orgs, source: @business, target: "repository")

    actor = RepositoryRulesetBypassActor.create(
      actor: enterprise_team,
      repository_ruleset: ruleset
    )

    assert_equal actor.actor_id, enterprise_team.id
    assert_predicate actor, :valid?
    assert_equal "EnterpriseTeam", actor.actor_type
    assert_equal "EnterpriseTeamBypassActor", actor.type
  end

  test "Enterprise Owner bypass actor is valid" do
    ruleset = create(:repository_ruleset, :targets_all_orgs, source: @business, target: "repository")

    actor = EnterpriseOwnerBypassActor.create(repository_ruleset: ruleset)

    assert_nil actor.actor_id
    assert_predicate actor, :valid?
    assert_equal actor.actor_type, "EnterpriseOwner"
    assert_equal "EnterpriseOwnerBypassActor", actor.type
  end

  test "RepositoryRole with write role is valid" do
    write_role = RepositoryRole.write_role
    actor = RepositoryRulesetBypassActor.create(
      actor: write_role,
      repository_ruleset: @ruleset
    )

    assert_equal actor.actor_id, write_role.id
    assert_predicate actor, :valid?
    assert_equal actor.actor_type, "RepositoryRole"
    assert_equal "RepositoryRoleBypassActor", actor.type
  end

  test "RepositoryRole with read role is not valid" do
    read_role = RepositoryRole.read_role
    actor = RepositoryRulesetBypassActor.new(
      actor: read_role,
      repository_ruleset: @ruleset
    )

    assert_equal actor.actor_id, read_role.id
    refute_predicate actor, :valid?
    assert_equal actor.actor_type, "RepositoryRole"
  end

  test "RepositoryRole with triage role is not valid" do
    triage_role = RepositoryRole.triage_role
    actor = RepositoryRulesetBypassActor.new(
      actor: triage_role,
      repository_ruleset: @ruleset
    )

    assert_equal actor.actor_id, triage_role.id
    refute_predicate actor, :valid?
    assert_equal actor.actor_type, "RepositoryRole"
  end

  test "CustomRole which inherits read is valid" do
    read_role = RepositoryRole.read_role
    custom_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: read_role.id)
    assert_equal read_role, custom_role.base_role

    actor = RepositoryRulesetBypassActor.new(
      actor: custom_role,
      repository_ruleset: @ruleset
    )

    assert_equal actor.actor_id, custom_role.id
    assert_predicate actor, :valid?
    assert_equal actor.actor_type, "RepositoryRole"
    assert_equal "RepositoryRoleBypassActor", actor.type
  end

  test "event_payload returns a hash of info about the bypass actor" do
    bypass_actor = RepositoryRulesetBypassActor.create(
      actor: @team_1,
      repository_ruleset: @ruleset
    )

    payload = bypass_actor.event_payload

    assert_equal payload, {
      id: bypass_actor.id,
      actor_id: @team_1.id,
      actor_type: "Team",
      bypass_mode: "always"
    }
  end

  test "teams must be accessible from the owning organization" do
    other_org = create(:business_plus_organization)
    other_team = create(:team, organization: other_org)

    actor = RepositoryRulesetBypassActor.new(
      actor: other_team,
      repository_ruleset: @ruleset
    )

    refute_predicate actor, :valid?
  end

  test "integrations must be accessible from the owning organization" do
    other_org = create(:business_plus_organization)
    other_integration = create(:integration, owner: other_org)

    actor = RepositoryRulesetBypassActor.new(
      actor: other_integration,
      repository_ruleset: @ruleset
    )

    refute_predicate actor, :valid?
  end

  context "#matching_user_ids" do
    test "returns user ids for teams" do
      child_team_member = create(:user)
      @org.add_member(child_team_member)

      child_team = create(:team, organization: @org, parent_team_id: @team_1.id, privacy: :closed)
      child_team.add_member(child_team_member)

      actor = RepositoryRulesetBypassActor.create!(
        actor: @team_1,
        repository_ruleset: @ruleset
      )

      assert_same_elements [@org_member_1.id, @org_member_2.id, child_team_member.id], RepositoryRulesetBypassActor.matching_user_ids(@org_repo, [actor])
    end

    test "returns user ids for system repository roles" do
      system_role = RepositoryRole.admin_role

      actor = RepositoryRulesetBypassActor.create!(
        actor: system_role,
        repository_ruleset: @ruleset
      )

      # Org admins implicitly have admin access to all repositories in an organization
      assert_same_elements [@org.admin.id, @org_member_1.id, @org_member_3.id], RepositoryRulesetBypassActor.matching_user_ids(@org_repo, [actor])
    end

    test "returns user ids for inherited system repository roles" do
      system_role = RepositoryRole.write_role

      actor = RepositoryRulesetBypassActor.create!(
        actor: system_role,
        repository_ruleset: @ruleset
      )

      # Org admins implicitly have admin access to all repositories in an organization
      assert_same_elements [@org.admin.id, @org_member_1.id, @org_member_2.id, @org_member_3.id], RepositoryRulesetBypassActor.matching_user_ids(@org_repo, [actor])
    end

    test "returns user ids for user assigned to custom repository roles" do
      custom_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: RepositoryRole.write_role.id)

      UserRole.create!(
        actor: @org_member_2,
        target: @org_repo,
        role: custom_role,
      )

      actor = RepositoryRulesetBypassActor.create!(
        actor: custom_role,
        repository_ruleset: @ruleset
      )

      assert_same_elements [@org_member_2.id], RepositoryRulesetBypassActor.matching_user_ids(@org_repo, [actor])
    end

    test "returns user ids for teams assigned to custom repository roles" do
      custom_role = create(:custom_repository_role, owner_id: @org.id, owner_type: "Organization", base_role_id: RepositoryRole.write_role.id)

      child_team_member = create(:user)
      @org.add_member(child_team_member)

      child_team = create(:team, organization: @org, parent_team_id: @team_1.id, privacy: :closed)
      child_team.add_member(child_team_member)

      UserRole.create!(
        actor: @team_1,
        target: @org_repo,
        role: custom_role,
      )

      actor = RepositoryRulesetBypassActor.create!(
        actor: custom_role,
        repository_ruleset: @ruleset
      )

      assert_same_elements [@org_member_1.id, @org_member_2.id, child_team_member.id], RepositoryRulesetBypassActor.matching_user_ids(@org_repo, [actor])
    end

    test "returns user ids for multiple actor types" do
      system_role = RepositoryRole.admin_role

      team_actor = RepositoryRulesetBypassActor.create!(
        actor: @team_1,
        repository_ruleset: @ruleset
      )

      role_actor = RepositoryRulesetBypassActor.create!(
        actor: system_role,
        repository_ruleset: @ruleset
      )

      # Org admins implicitly have admin access to all repositories in an organization
      assert_same_elements [@org.admin.id, @org_member_1.id, @org_member_2.id, @org_member_3.id], RepositoryRulesetBypassActor.matching_user_ids(@org_repo, [team_actor, role_actor])
    end
  end
end
