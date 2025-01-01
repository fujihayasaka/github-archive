# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamCreatorTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "org-admin")
    @member = create(:user, login: "org-member")
    @org  = create(:organization, admin: @user, plan: "bronze")

    # So we don't get errors about trying to remove the last admin from the org
    @org.add_admin(create(:user, login: "extra-org-admin"))
    @org.add_member(@member)

    @integration = create(:integration, default_permissions: { "members" => :write })
    @installation = make_integration_installation(
      target: @org,
      integration: @integration,
    )
  end

  test "adds a new team with the owner" do
    assert_difference("Team.count", 1) do
      Team::Creator.create_team(@user, @org,
        { name: "team", permission: "pull" },
        maintainers: nil)
    end
  end

  test "does not create a new team if trying to nest under an enterprise managed team" do
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

    enterprise_team = create :enterprise_team
    et_managed_team = create :team, organization: @org, privacy: :closed
    EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team, organization: @org, team: et_managed_team)

    assert_no_difference("Team.count") do
      new_team = Team::Creator.create_team(@user, @org,
        { name: "team", permission: "pull", parent_team_id: et_managed_team.id },
        maintainers: nil)
      assert_equal ["This team cannot have an enterprise team managed team as a parent team."], new_team.errors[:base]
    end
  end

  test "adds a new team from a team member" do
    assert_difference("Team.count", 1) do
      Team::Creator.create_team(@member, @org,
        { name: "team", permission: "pull" },
        maintainers: nil)
    end
  end

  test "asigns the right permission to the group" do
    team = Team::Creator.create_team(@user, @org,
      { name: "team", permission: "pull" },
      maintainers: nil)
    assert_equal "pull", team.permission
  end

  test "sets the attributes of the team" do
    team = Team::Creator.create_team(@user, @org,
      { name: "the-team", description: "stuff", ldap_dn: "" },
      maintainers: nil)
    assert_equal "the-team", team.name
    assert_equal "stuff", team.description
  end

  test "adds specified initial members" do
    team = Team::Creator.create_team(@user, @org,
      { name: "team", permission: "pull" },
      maintainers: [@user])
    assert team.member?(@user)
  end

  test "new team gets permissions on forks" do
    @org.allow_private_repository_forking(actor: @user)

    repo = create(:private_repository, name: "new_team_repo", owner: @org)

    team = Team::Creator.create_team(@user, @org,
      { name: "team" }, maintainers: nil)
    team.add_repository(repo, :pull)
    fork = create(:fork_repository, forker: @user, fork_repo: repo)

    newteam = Team::Creator.create_team(@user, @org,
      { name: "newteam" }, maintainers: nil)
    perform_enqueued_jobs(only: [TeamAddForksJob]) do
      newteam.add_repository(repo, :pull)
    end
    assert_equal "pull", newteam.permission_for(fork)
  end

  test "new team does not get permissions on public forks" do
    repo = create(:public_repository, name: "new_team_pubrepo", owner: @org)

    fork = create(:fork_repository, forker: @user, fork_repo: repo)

    newteam = Team::Creator.create_team(@user, @org,
      { name: "newteam" }, maintainers: nil)
    perform_enqueued_jobs(only: [DeliverHookEventJob]) do
      newteam.add_repository(repo, :pull)
    end
    assert_nil newteam.permission_for(fork)
  end

  test "new team does not get permissions on fork to org" do
    @org2user = create(:user, login: "org2-admin")
    @org2  = create(:organization, admin: @org2user, plan: "bronze")

    repo = create(:private_repository, name: "fork_to_org", owner: @org)
    repo.allow_private_repository_forking(actor: @user)

    team = Team::Creator.create_team(@user, @org,
      { name: "team" }, maintainers: nil)
    team.add_member(@org2user)
    team.add_repository(repo, :pull)

    fork = create(:fork_repository, forker: @org2user, fork_repo: repo, organization: @org2)

    newteam = Team::Creator.create_team(@user, @org,
      { name: "newteam" }, maintainers: nil)
    newteam.add_repository(repo, :pull)
    assert_nil newteam.permission_for(fork)
  end

  test "sets the initial members as a team maintainer" do
    maintainer = create(:user, login: "team-maintainer")
    team       = Team::Creator.create_team(maintainer, @org, { name: "team" }, maintainers: [maintainer])
    assert team.maintainer?(maintainer)
  end

  test "adds owners as regular members if specified as maintainers" do
    org_owner = create(:user, login: "org-owner")
    @org.add_admin(org_owner)

    team = Team::Creator.create_team(@user, @org,
      { name: "team", permission: "pull" },
      maintainers: [org_owner])

    assert team.member?(org_owner)
    assert team.adminable_by?(org_owner)
    refute team.maintainer?(org_owner)
  end

  test "defaults the creator to a maintainer if" \
    "creator is not an org admin" \
    "and creator is a user" do
    team = Team::Creator.create_team(
      @member,
      @org,
      { name: "team", permission: "pull" },
      maintainers: [@user],
    )
    assert_same_elements [@member], team.maintainers
    assert team.adminable_by?(@member)
  end

  test "defaults the creator to a maintainer if" \
    "no maintainers passed in" \
    "creator is not an org admin" \
    "and creator is a user" do
    team = Team::Creator.create_team(
      @member,
      @org,
      { name: "team", permission: "pull" },
      maintainers: [],
    )
    assert_same_elements [@member], team.maintainers
  end

  test "does not default the creator to a maintainer if" \
    "no maintainers passed in" \
    "creator is an org admin" do
    team = Team::Creator.create_team(
      @user,
      @org,
      { name: "team", permission: "pull" },
      maintainers: [],
    )
    assert_empty team.maintainers
  end

  test "does not default the creator to a maintainer if" \
    "no maintainers passed in" \
    "creator is not of type User" do
    bot = make_integration_installation(
      target: @org,
      permissions: { "members" => :write },
    ).bot

    team = Team::Creator.create_team(
      bot,
      @org,
      { name: "team", permission: "pull" },
      maintainers: [],
    )
    assert_empty team.maintainers
  end

  test "does not default the creator to a maintainer if" \
    "maintainers passed in" do
    team = Team::Creator.create_team(
      @user,
      @org,
      { name: "team", permission: "pull" },
      maintainers: [@member],
    )
    assert_same_elements [@member], team.maintainers
  end

  test "allow apps to create nested teams under teams they've created" do
    # Manually assign the installation for these tests, as this would be carried out
    # during API request by an installation to create teams.
    bot = @integration.bot
    bot.installation = @installation

    parent_team = Team::Creator.create_team(
      bot,
      @org,
      { name: "parent_team", privacy: "closed" },
      maintainers: [],
    )
    assert_predicate parent_team, :persisted?

    nested_team = Team::Creator.create_team(
      bot,
      @org,
      { name: "nested_team", privacy: "closed", parent_team_id: parent_team.id },
      maintainers: [],
    )
    assert_predicate nested_team, :persisted?
    assert_equal parent_team, nested_team.parent_team
  end

  test "prevents apps from nesting teams under teams they didn't create" do
    parent_team = Team::Creator.create_team(
      @user,
      @org,
      { name: "parent_team", privacy: "closed" },
      maintainers: [],
    )
    assert_predicate parent_team, :persisted?

    bot = @integration.bot
    bot.installation = @installation

    nested_team = Team::Creator.create_team(
      bot,
      @org,
      { name: "nested_team", privacy: "closed", parent_team_id: parent_team.id },
      maintainers: [],
    )
    assert_predicate nested_team, :persisted?
    assert_nil nested_team.parent_team
  end

  test "prevents apps from creating teams when permissions are updated" do
    bot = @integration.bot
    bot.installation = @installation

    parent_team = Team::Creator.create_team(
      bot,
      @org,
      { name: "parent_team", privacy: "closed" },
      maintainers: [],
    )
    assert_predicate parent_team, :persisted?

    # downgrade permissions
    @integration.default_permissions = { "members" => :read }
    @integration.save!
    @integration.reload
    @installation.update_version(editor: @org.admins.first, version: @integration.latest_version, entry_point: :test_case)
    @installation.reload
    assert_equal @integration.latest_version, @installation.version

    nested_team = Team::Creator.create_team(
      bot,
      @org,
      { name: "nested_team", privacy: "closed", parent_team_id: parent_team.id },
      maintainers: [],
    )
    refute_predicate nested_team, :persisted?
    assert_equal ["This GitHub App doesn't have permissions to create teams"], nested_team.errors[:base]
  end
end

if GitHub.enterprise?
  class TeamCreatorWithLdapAuthenticationTest < GitHub::TestCase
    include AuthenticationHelpers::LDAP

    fixtures do
      @user = create(:user, login: "org-admin")
      @org  = create(:organization, admin: @user, plan: "bronze")

      # So we don't get errors about trying to remove the last admin from the org
      @org.add_admin(create(:user, login: "extra-org-admin"))
    end

    setup_once do
      LdapHelper.setup_ldap_authentication
    end

    teardown_once do
      LdapHelper.teardown_ldap_authentication
    end

    ldap_test "creates a team without a mapping" do
      assert_difference "Team.count" do
        team = Team::Creator.create_team(@user, @org,
          { name: "howdy", permission: "pull" },
          maintainers: nil)
        assert_nil team.ldap_mapping
      end
    end

    ldap_test "creates a team as a GitHub App" do
      installation = make_integration_installation(target: @org, permissions: {
        "organization_administration" => :write,
        "members" => :write,
      })

      assert_difference "Team.count" do
        team = Team::Creator.create_team(installation, @org,
          { name: "howdy", permission: "pull" },
          maintainers: nil)
        assert_nil team.ldap_mapping
      end
    end

    ldap_test "it maps the ldap group assigned to the team" do
      assert_difference("Team.count", 1) do
        team = Team::Creator.create_team(@user, @org,
          { name: "enterprise", permission: "pull", ldap_dn: "cn=Enterprise,ou=teams,dc=github,dc=com" },
          maintainers: nil)

        assert_equal "cn=Enterprise,ou=teams,dc=github,dc=com", team.ldap_mapping.dn
      end
    end

    ldap_test "it defaults the name to the LDAP Group CN" do
      assert_difference "Team.count" do
        team = Team::Creator.create_team(@user, @org,
          { ldap_dn: "cn=enterprise,ou=teams,dc=github,dc=com" },
          maintainers: nil)
        assert_equal "Enterprise", team.name
      end
    end

    ldap_test "it defaults the persmission to pull only" do
      assert_difference "Team.count" do
        team = Team::Creator.create_team(@user, @org,
          { ldap_dn: "cn=enterprise,ou=teams,dc=github,dc=com" },
          maintainers: nil)
        assert_equal "pull", team.permission
      end
    end

    ldap_test "it adds the group members to the team" do
      calavera = create(:user, login: "calavera")
      calavera.map_ldap_entry("uid=calavera,ou=users,dc=github,dc=com")
      ben = create(:user, login: "ben")
      ben.map_ldap_entry("uid=benburkert,ou=users,dc=github,dc=com")

      team = T.let(nil, T.nilable(Team))
      perform_enqueued_jobs(only: [LdapTeamSyncJob]) do
        team = Team::Creator.create_team(@user, @org,
          { name: "enterprise", permission: "pull", ldap_dn: "cn=enterprise,ou=teams,dc=github,dc=com" },
          maintainers: [@user])
      end

      assert_same_elements [calavera, ben], team&.members
    end

    ldap_test "doesn't save the team with an invalid ldap_dn" do
      team = Team::Creator.create_team(@user, @org,
        { name: "enterprise", permission: "pull", ldap_dn: "foobar" },
        maintainers: [@user])

      assert team.new_record?, "Expected to not persist the team"
      refute team.errors.empty?, "Expected to have errors"
      assert_equal "LDAP group with DN foobar doesn't exist", team.errors[:base].first
    end

    ldap_test "doesn't save the team when created from a member" do
      team = Team::Creator.create_team(@member, @org,
        { name: "enterprise", permission: "pull", ldap_dn: "cn=enterprise,ou=teams,dc=github,dc=com" },
        maintainers: [@member])

      assert_predicate team, :new_record?
      refute_predicate team.errors, :empty?
      assert team.errors[:base].any? { |m| m == "Only organization administrators can setup LDAP mappings for a team" }, "Expected to error for non org admins"
    end
  end
end

module ScimManagedTeamCreatorSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def create_team(creator: @owner, organization: @org, group_mappings: [], parent_team_id: nil)
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      Team::Creator.create_team(
        creator,
        organization,
        { name: "team-#{SecureRandom.hex(6)}", privacy: "closed", parent_team_id: parent_team_id },
        maintainers: nil,
        group_mappings: group_mappings,
      )
    end
  end

  def test_creates_a_new_team_with_the_owner
    assert_difference("Team.count", 1) do
      team = create_team

      assert_same_elements [@owner], team.members
    end
  end

  def test_creates_a_new_team_with_group_members
    assert_difference("Team.count", 1) do
      team = create_team(group_mappings: @group_mappings)

      assert_same_elements @external_group_users, team.members
      assert_same_elements @external_group_users + [@owner], @org.members
    end
  end

  def test_does_not_create_team_with_parent_team_and_group_mapping
    assert_difference("Team.count", 1) do
      parent_team = create_team
      assert_predicate parent_team, :persisted?
      assert_same_elements [@owner], parent_team.members

      team = create_team(parent_team_id: parent_team.id, group_mappings: @group_mappings)
      refute_predicate team, :persisted?
      assert_equal ["This team cannot have a parent team when being linked to an identity provider group."], team.errors[:base]
    end
  end

  def test_creates_team_with_parent_team_and_no_group_mapping
    assert_difference("Team.count", 2) do
      parent_team = create_team
      assert_predicate parent_team, :persisted?

      team = create_team(parent_team_id: parent_team.id)
      assert_predicate team, :persisted?
      assert_equal parent_team.id, team.parent_team_id
    end
  end
end

class EmuTeamCreatorTest < GitHub::TestCase
  include ScimManagedTeamCreatorSharedTests

  fixtures do
    @owner = @user = create(:emu, :owner, login: "org-admin")
    @enterprise = @owner.enterprise_managed_business

    @org = create :organization, business: @enterprise, admin: @owner
    @external_group = create :external_group, :with_members, business: @enterprise, number_of_members: 2
    @external_group_users = @external_group.external_identity_group_memberships.map(&:external_identity).map(&:user)
    @group_mappings = [{ group_id: @external_group.id.to_s }]
  end
end unless GitHub.single_business_environment?

class GhesWithSCIMTeamCreatorTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include ScimManagedTeamCreatorSharedTests

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @enterprise = create(:global_business)

    @owner = @user = create :ghes_scim_user, :admin, business: @enterprise

    @org = create :organization, business: @enterprise, admin: @owner
    @external_group = create :external_group, :with_members, business: @enterprise, number_of_members: 2
    @external_group_users = @external_group.external_identity_group_memberships.map(&:external_identity).map(&:user)
    @group_mappings = [{ group_id: @external_group.id.to_s }]
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end
end if GitHub.single_business_environment?
