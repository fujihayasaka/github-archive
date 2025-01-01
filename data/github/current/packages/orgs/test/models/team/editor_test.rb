# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamEditorTest < GitHub::TestCase
  include AuthenticationHelpers::LDAP
  fixtures do
    @user = create(:user, login: "org-admin")
    @member = create(:user, login: "org-member")

    @org  = create(:organization, admin: @user, plan: "bronze")
    @org.add_member(@member)
    @team = create(:team, organization: @org)

    @saml_org = create(:business_plus_org, login: "saml-org", admin: @user)
    @saml_provider = create(:organization_saml_provider, organization: @saml_org, issuer: "https://sts.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/")
    create :team_sync_tenant, organization: @saml_org
    assert_predicate @saml_org, :show_team_sync_feature? if GitHub.team_synchronization_available?

    @saml_team = create :team, organization: @saml_org, privacy: :secret
    @saml_team.add_member(@user)
    @saml_team.promote_maintainer(@user)
  end

  def update_team(ldap_dn, updater = @user)
    Team::Editor.update_team(@team, name: "bar", description: "foo", updater: updater, permission: "admin", ldap_dn: ldap_dn)
  end

  test "updates the team attributes" do
    Team::Editor.update_team(@team, name: "bar", description: "foo", permission: "admin")
    assert_equal "bar", @team.name
    assert_equal "foo", @team.description
    assert_equal "admin", @team.permission
  end

  test "ignores unused attributes" do
    update_team("foo")
  end

  test "preserves existing group mappings when the group_mappings argument is not provided", team_synchronization_available: true do
    group_id = "244145f2-c20f-43ae-bc6a-ffcd0ec0ccef"
    @saml_team.group_mappings.create!(group_id: group_id, group_name: "bar", group_description: "Developers")

    Team::Editor.update_team(@saml_team, description: "foo")

    assert_equal "foo", @saml_team.description
    assert_equal [group_id], @saml_team.reload.group_mappings.map(&:group_id)
  end

  context "with ldap enabled" do
    include AuthenticationHelpers::LDAP

    setup_once do # rubocop:disable GitHub/NestedSetupTeardown
      LdapHelper.setup_ldap_authentication
    end

    teardown_once do # rubocop:disable GitHub/NestedSetupTeardown
      LdapHelper.teardown_ldap_authentication
    end

    ldap_test "creates a new ldap mapping when it doesn't exist" do
      T.unsafe(self).update_team("cn=Enterprise,ou=teams,dc=github,dc=com")
      assert_equal "cn=Enterprise,ou=teams,dc=github,dc=com", @team.ldap_mapping.dn
    end

    ldap_test "update an existent ldap mapping" do
      @team.create_ldap_mapping(dn: "bar")
      T.unsafe(self).update_team("cn=Enterprise,ou=teams,dc=github,dc=com")
      assert_equal "cn=Enterprise,ou=teams,dc=github,dc=com", @team.ldap_mapping.dn
    end

    ldap_test "don't allow an update to ldap mapping when updater is not an org owner" do
      @team.create_ldap_mapping(dn: "bar")
      T.unsafe(self).update_team("cn=Enterprise,ou=teams,dc=github,dc=com", @member)

      assert_equal "bar", @team.ldap_mapping.dn
      refute_predicate @team.errors, :empty?
      assert @team.errors[:base].any? { |m| m == "Only organization administrators can setup LDAP mappings for a team" }, "Expected to error for non org admins"
    end

    ldap_test "update team without updating LDAP mapping if unchanged" do
      dn = "cn=enterprise,ou=teams,dc=github,dc=com"
      mapping = @team.map_ldap_entry(dn)
      # sync to set `synced` status
      GitHub::LDAP::TeamSync.new.perform(dn)
      assert @team.reload.ldap_synced?, "team should be synced (status: #{@team.ldap_mapping.sync_status})"

      Team::Editor.update_team(@team, name: "changed", ldap_dn: dn)
      assert @team.errors.empty?, @team.errors.to_a.to_sentence

      assert_equal "changed", @team.name, "team name should've been updated"
      assert @team.ldap_synced?, "team should be synced (status: #{@team.ldap_mapping.sync_status})"
    end

    ldap_test "removes the ldap mapping with the group is empty" do
      @team.create_ldap_mapping(dn: "bar")
      T.unsafe(self).update_team("")
      refute @team.ldap_mapping, "Expected to not have ldap mapping"
    end

    ldap_test "doesn't try to remove the ldap mapping when it didn't exist" do
      T.unsafe(self).update_team("")
      refute @team.ldap_mapping, "Expected to not have ldap mapping"
    end

    ldap_test "doesn't try to remove the ldap mapping when the attribute is nil" do
      @team.create_ldap_mapping(dn: "bar")
      T.unsafe(self).update_team(nil)
      assert_equal "bar", @team.ldap_mapping.dn
    end

    ldap_test "doesn't update the team when the ldap group doesn't exist" do
      @team.create_ldap_mapping(dn: "bar")
      updated = T.unsafe(self).update_team("foobar")

      refute updated, "Expected to not update the team"
      assert_equal "LDAP group with DN foobar doesn't exist", @team.errors[:base].first
    end
  end
end

module ScimManagedTeamEditorSharedTests
  extend T::Helpers
  requires_ancestor { GitHub::TestCase }

  def update_team(team, group_mappings = [], updater = @user)
    Team::Editor.update_team(
      team,
      group_mappings: group_mappings,
      updater: updater,
      permission: "admin",
    )
  end

  def create_team(group_mappings: [], creator: @owner, organization: @org)
    Team::Creator.create_team(
      creator,
      organization,
      { name: "team-#{SecureRandom.hex(6)}", privacy: "closed", permission: "pull" },
      maintainers: nil,
      group_mappings: group_mappings,
    )
  end

  def test_can_update_parent_team_of_an_unlinked_team
    # this team will have owner as a member
    team = create_team
    parent_team = create_team

    result = Team::Editor.update_team(
      team,
      parent_team_id: parent_team.id
    )

    assert result
    assert_equal parent_team.id, team.reload.parent_team_id
  end

  def test_cannot_update_parent_team_of_a_linked_team
    # this team will have owner as a member
    parent_team = create_team
    # create a linked team
    team = T.let(nil, T.nilable(Team))
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      team = create_team(group_mappings: @group_mappings1)
    end

    result = Team::Editor.update_team(
      team,
      parent_team_id: parent_team.id
    )

    refute result
    assert_nil team&.reload.parent_team_id
  end

  def test_can_update_unlinked_team_when_group_mapping_is_nil
    team = create_team
    result = Team::Editor.update_team(
      team,
      name: "new-team"
    )

    assert result
    assert_equal "new-team", team.reload.name
  end

  def test_can_update_a_linked_team_when_group_mapping_is_nil
    # create a linked team
    team = T.let(nil, T.nilable(Team))
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      team = create_team(group_mappings: @group_mappings1)
    end

    assert_predicate team, :externally_managed?
    result = Team::Editor.update_team(
      team,
      name: "new-team"
    )

    assert result
    assert_equal "new-team", team&.reload.name
  end

  def test_can_update_team_with_explicit_members
    # this team will have owner as a member
    team = create_team
    assert_nil team.description

    assert_same_elements [@owner], team.members
    assert_same_elements [@owner], @org.members

    team.description = "Updated description"
    assert update_team(team)

    assert_equal "Updated description", team.reload.description

    assert_same_elements [@owner], team.members
    assert_same_elements [@owner], @org.members
  end

  def test_cannot_link_team_with_explicit_members_to_an_external_group
    # this team will have owner as a member
    team = T.let(nil, T.nilable(Team))
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      team = create_team
    end

    assert_same_elements [@owner], team&.members
    assert_same_elements [@owner], @org.members

    refute update_team(team, @group_mappings1)

    assert_same_elements [@owner], team&.members
    assert_same_elements [@owner], @org.members
  end

  def test_can_link_team_without_explicit_members_to_an_external_group
    # this team will have owner as a member
    team = T.let(nil, T.nilable(Team))
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      team = create_team
    end
    team&.remove_member(@owner)

    refute_predicate team&.members, :any?
    assert_same_elements [@owner], @org.members

    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      assert update_team(team, @group_mappings1)
    end

    assert_same_elements @external_group_users1, team&.members
    assert_same_elements @external_group_users1 + [@owner], @org.members
  end

  def test_update_group_mappings_switches_team_members_and_organization_members
    team = T.let(nil, T.nilable(Team))
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      team = create_team(group_mappings: @group_mappings1)
    end

    assert_same_elements @external_group_users1, team&.members
    assert_same_elements @external_group_users1 + [@owner], @org.members

    perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      assert update_team(team, @group_mappings2)
    end

    assert_same_elements @external_group_users2, team&.members
    assert_same_elements @external_group_users2 + [@owner], @org.members
  end

  def test_update_group_mappings_to_empty_removes_members
    team = T.let(nil, T.nilable(Team))
    perform_enqueued_jobs only: ExternalGroupTeamLinkJob do
      team = create_team(group_mappings: @group_mappings1)
    end

    assert_same_elements @external_group_users1, team&.members
    assert_same_elements @external_group_users1 + [@owner], @org.members

    perform_enqueued_jobs(only: [ExternalGroupTeamLinkJob, ExternalGroupTeamUnlinkJob, RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      assert update_team(team)
    end

    refute_predicate team&.members, :any?
    assert_same_elements [@owner], @org.members
  end
end

class EmuTeamEditorTest < GitHub::TestCase
  include ScimManagedTeamEditorSharedTests

  fixtures do
    @owner = @user = create(:emu, :owner, login: "org-admin")
    @enterprise = @user.enterprise_managed_business

    @org = create :organization, business: @enterprise, admin: @owner

    @external_group1 = create :external_group, :with_members, business: @enterprise, number_of_members: 2
    @external_group_users1 = @external_group1.external_identity_group_memberships.map(&:external_identity).map(&:user)
    @group_mappings1 = [{ group_id: @external_group1.id.to_s }]

    @external_group2 = create :external_group, :with_members, business: @enterprise, number_of_members: 3
    @external_group_users2 = @external_group2.external_identity_group_memberships.map(&:external_identity).map(&:user)
    @group_mappings2 = [{ group_id: @external_group2.id.to_s }]
  end
end unless GitHub.single_business_environment?

class GhesWithSCIMTeamEditorTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include ScimManagedTeamEditorSharedTests

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @enterprise = create(:global_business)

    @owner = @user = create :ghes_scim_user, :admin, business: @enterprise

    @org = create :organization, business: @enterprise, admin: @owner

    @external_group1 = create :external_group, :with_members, business: @enterprise, number_of_members: 2
    @external_group_users1 = @external_group1.external_identity_group_memberships.map(&:external_identity).map(&:user)
    @group_mappings1 = [{ group_id: @external_group1.id.to_s }]

    @external_group2 = create :external_group, :with_members, business: @enterprise, number_of_members: 3
    @external_group_users2 = @external_group2.external_identity_group_memberships.map(&:external_identity).map(&:user)
    @group_mappings2 = [{ group_id: @external_group2.id.to_s }]
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end
end if GitHub.single_business_environment?
