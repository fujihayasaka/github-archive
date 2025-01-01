# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamPermissionsTest < GitHub::TestCase
  fixtures do
    @org_admin = create(:user, login: "org-admin")
    @org = create(:organization, admin: @org_admin)
    @closed_team = create(:team, organization: @org, privacy: :closed)
    @secret_team = create(:team, organization: @org, privacy: :secret)

    unless GitHub.enterprise?
      @emu_owner = create :emu
      @business = @emu_owner.enterprise_managed_business
      @enterprise_team = create(:enterprise_team, business: @business)
      @emu_org = create :organization, business: @business, admin: @emu_owner
      @emu_org_team = create(:team, organization: @emu_org, privacy: :closed)
      EnterpriseTeamOrganizationMapping.create!(enterprise_team: @enterprise_team, organization: @emu_org, team: @emu_org_team)
    end
  end

  context "#async_visible_to?" do
    test "resolves to false when user is nil" do
      assert_equal false, @closed_team.async_visible_to?(nil).sync
    end

    test "resolves to false for a non-org member" do
      non_org_member = create(:user)
      assert_equal false, @closed_team.async_visible_to?(non_org_member).sync
    end

    test "resolves to false for a non-team member on a secret team" do
      org_member = create(:user)
      @org.add_member(org_member)

      assert_equal false, @secret_team.async_visible_to?(org_member).sync
    end

    test "resolves to false for an unprivileged integration's bot user" do
      integration = create(:integration, default_permissions: {})
      installation = integration
        .install_on(@org, repositories: [], installer: @org_admin, entry_point: :test_case)
        .installation

      assert_equal false, @closed_team.async_visible_to?(installation.bot).sync
    end

    test "resolves to true for an org member on a closed team" do
      org_member = create(:user)
      @org.add_member(org_member)

      assert @closed_team.async_visible_to?(org_member).sync
    end

    test "resolves to true for a team member of a secret team" do
      team_member = create(:user)
      @secret_team.add_member(team_member)

      assert @secret_team.async_visible_to?(team_member).sync
    end

    test "resolves to true for an org admin" do
      assert @secret_team.async_visible_to?(@org_admin).sync
    end

    test "resolves to true for a privileged integration's bot user with the `members` permission" do
      integration = create(:integration, default_permissions: { members: :read })
      installation = integration
        .install_on(@org, repositories: [], installer: @org_admin, entry_point: :test_case)
        .installation

      assert @secret_team.async_visible_to?(installation.bot).sync
    end

    test "resolves to true for a privileged integration's bot user with the `team_discussions` permission" do
      integration = create(:integration, default_permissions: { team_discussions: :read })
      installation = integration
        .install_on(@org, repositories: [], installer: @org_admin, entry_point: :test_case)
        .installation

      assert @secret_team.async_visible_to?(installation.bot).sync
    end
  end

  context "#async_can_create_team_discussion?" do
    test "resolves to false when user is nil" do
      refute @closed_team.async_can_create_team_discussion?(nil).sync
    end

    test "resolves to false when discussions are disabled" do
      @org.disallow_team_discussions(actor: @org_admin)
      refute @closed_team.async_can_create_team_discussion?(@org_admin).sync
    end

    test "resolves to true for an org admin" do
      assert @secret_team.async_can_create_team_discussion?(@org_admin).sync
    end

    test "resolves to false for a non-org member" do
      rando = create(:user, login: "rando")
      refute @closed_team.async_can_create_team_discussion?(@rando).sync
    end

    test "resolves to true for an org member on a closed team" do
      org_member = create(:user, login: "org-member")
      @org.add_member(org_member)
      assert @closed_team.async_can_create_team_discussion?(org_member).sync
    end

    test "resolves to true for a team member on a secret team" do
      team_member = create(:user, login: "secret-team-member")
      @secret_team.add_member(team_member)
      assert @secret_team.async_can_create_team_discussion?(team_member).sync
    end

    test "resolves to false for a non-team member on a secret team" do
      closed_team_member = create(:user, login: "closed-team-member")
      @closed_team.add_member(closed_team_member)
      refute @secret_team
        .async_can_create_team_discussion?(closed_team_member)
        .sync
    end

    test "resolves to false for a bot without write permissions on team discussions" do
      integration = create(:integration, default_permissions: { team_discussions: :read })
      installation = integration
        .install_on(@org, repositories: [], installer: @org_admin, entry_point: :test_case)
        .installation
      bot = installation.bot

      refute @secret_team
        .async_can_create_team_discussion?(bot)
        .sync
    end

    test "resolves to true for a bot with write permissions on team discussions" do
      integration = create(:integration, default_permissions: { team_discussions: :write })
      installation = integration
        .install_on(@org, repositories: [], installer: @org_admin, entry_point: :test_case)
        .installation
      bot = installation.bot

      assert @secret_team
        .async_can_create_team_discussion?(bot)
        .sync
    end

    test "resolves to false for an installation without write permissions on team discussions" do
      integration = create(:integration, default_permissions: { team_discussions: :read })
      installation = integration
        .install_on(@org, repositories: [], installer: @org_admin, entry_point: :test_case)
        .installation

      refute @secret_team
        .async_can_create_team_discussion?(installation)
        .sync
    end

    test "resolves to true for an installation with write permissions on team discussions" do
      integration = create(:integration, default_permissions: { team_discussions: :write })
      installation = integration
        .install_on(@org, repositories: [], installer: @org_admin, entry_point: :test_case)
        .installation

      assert @secret_team
        .async_can_create_team_discussion?(installation)
        .sync
    end
  end

  context "#async_permit for enterprise_managed_team", skip_enterprise: true do
    test "Org owner can admin enterprise managed organization team if ff disabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(false)

      assert @emu_org_team.adminable_by?(@emu_owner)
    end

    test "Org owner cannot admin enterprise managed organization team if ff enabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)

      refute @emu_org_team.adminable_by?(@emu_owner)
    end unless GitHub.single_business_environment?

    test "Org owner can still read enterprise managed organization team" do
      assert @emu_org_team.permit?(@emu_owner, :read)
    end
  end
end
