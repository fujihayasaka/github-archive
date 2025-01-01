# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryCodeScanningDependencyPermissionTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @owner       = create(:paid_user)
    @random_user = create(:user)
    @pub_user_repo        = create(:public_repository, :minimal, owner: @owner)

    @org_admin = create(:paid_user)
    @org       = create(:business_plus_organization, admin: @org_admin)
    @pub_org_repo = create(:public_repository, :minimal, owner: @org)
    @priv_org_repo = create(:private_repository, :minimal, owner: @org)
    @priv_org_repo_write = create(:private_repository, :minimal, owner: @org)
    @priv_org_repo_read = create(:private_repository, :minimal, owner: @org)

    @team        = create(:team, organization: @org)
    @team_member = create(:user)
    @team.add_member @team_member
    @team.add_repository @priv_org_repo_write, :write
    @team.add_repository @priv_org_repo_read, :read

    @staff_user        = create(:staff_admin_user)
    @staff_unlock_user = create(:staff_admin_user)
    admin_unlock_repo(@staff_unlock_user, @priv_org_repo_write)

    @reader_role = create_custom_role(owner: @org, base_role: :read, fgps: [:read_code_scanning])
    @writer_role = create_custom_role(owner: @org, base_role: :read, fgps: [:write_code_scanning])
    @delete_alerts_role = create_custom_role(owner: @org, base_role: :read, fgps: [:delete_alerts_code_scanning])
    @custom_reader_user = create(:user)
    @custom_writer_user = create(:user)
    @custom_delete_alerts_user = create(:user)
    @priv_org_repo_write.add_member(@custom_reader_user, action: @reader_role.name)
    @priv_org_repo_write.add_member(@custom_writer_user, action: @writer_role.name)
    @priv_org_repo_write.add_member(@custom_delete_alerts_user, action: @delete_alerts_role.name)

    @reader_team        = create(:team, organization: @org)
    @reader_team_member = create(:user)
    @reader_team.add_member @reader_team_member
    @reader_team.add_repository @priv_org_repo_write, @reader_role.name
    @writer_team        = create(:team, organization: @org)
    @writer_team_member = create(:user)
    @writer_team.add_member @writer_team_member
    @writer_team.add_repository @priv_org_repo_write, @writer_role.name
    @delete_alerts_team = create(:team, organization: @org)
    @delete_alerts_team_member = create(:user)
    @delete_alerts_team.add_member @delete_alerts_team_member
    @delete_alerts_team.add_repository @priv_org_repo_write, @delete_alerts_role.name

    @security_manager_team = create(:security_manager_team, organization: @org)

    @admin_team = create(:team, organization: @org)
    @admin_team.add_repository @priv_org_repo, :admin
  end

  setup do
    if GitHub.enterprise?
      GitHub::Enterprise.license.stubs(:advanced_security_enabled).returns(true)
    else
      @org.mark_advanced_security_as_purchased_for_entity(actor: @org_admin)
    end
    GitHub.stubs(:code_scanning_enabled?).returns(true)

    @pub_org_repo.enable_advanced_security!(actor: @org_admin) if GitHub.enterprise?
    @priv_org_repo.enable_advanced_security!(actor: @org_admin)
    @priv_org_repo_write.enable_advanced_security!(actor: @org_admin)
    @priv_org_repo_read.enable_advanced_security!(actor: @org_admin)
  end

  context "#code_scanning_base_permissions" do
    # dotcom only because GHAS is not allowed for user-owned on GHES
    test "owner access", skip_enterprise: true do
      assert @pub_user_repo.code_scanning_readable_by?(@owner)
      assert @pub_user_repo.code_scanning_writable_by?(@owner)
      assert @pub_user_repo.code_scanning_analyses_deletable_by?(@owner)
    end

    test "random user no access" do
      refute @pub_user_repo.code_scanning_readable_by?(@random_user)
      refute @pub_user_repo.code_scanning_writable_by?(@random_user)
      refute @pub_user_repo.code_scanning_analyses_deletable_by?(@random_user)
    end

    test "org admin access" do
      assert @priv_org_repo_write.code_scanning_readable_by?(@org_admin)
      assert @priv_org_repo_write.code_scanning_writable_by?(@org_admin)
      assert @priv_org_repo_write.code_scanning_analyses_deletable_by?(@org_admin)
    end

    test "team admin access" do
      test_user = create(:user)
      @org.add_member(test_user, action: :read)

      @admin_team.add_member test_user
      assert @priv_org_repo.code_scanning_readable_by?(test_user)
      assert @priv_org_repo.code_scanning_writable_by?(test_user)
      assert @priv_org_repo.code_scanning_analyses_deletable_by?(test_user)

      @admin_team.remove_member test_user
      refute @priv_org_repo.code_scanning_readable_by?(test_user)
      refute @priv_org_repo.code_scanning_writable_by?(test_user)
      refute @priv_org_repo.code_scanning_analyses_deletable_by?(test_user)
    end

    test "team write access" do
      assert @priv_org_repo_write.code_scanning_readable_by?(@team_member)
      assert @priv_org_repo_write.code_scanning_writable_by?(@team_member)
      refute @priv_org_repo_write.code_scanning_analyses_deletable_by?(@team_member)
    end

    test "team read no access" do
      refute @priv_org_repo_read.code_scanning_readable_by?(@team_member)
      refute @priv_org_repo_read.code_scanning_writable_by?(@team_member)
      refute @priv_org_repo_read.code_scanning_analyses_deletable_by?(@team_member)
    end

    test "staff have read access to alerts on dotcom" do
      if GitHub.enterprise?
        refute @pub_org_repo.code_scanning_readable_by?(@staff_user)
      else
        assert @pub_org_repo.code_scanning_readable_by?(@staff_user)
      end
      refute @pub_org_repo.code_scanning_writable_by?(@staff_user)
      refute @pub_org_repo.code_scanning_analyses_deletable_by?(@staff_user)
    end

    test "staff can downgrade by disabling employee mode", skip_enterprise: true do
      @staff_user.disable_employee_mode
      refute @pub_user_repo.code_scanning_readable_by?(@staff_user)
      refute @pub_user_repo.code_scanning_writable_by?(@staff_user)
      refute @pub_user_repo.code_scanning_analyses_deletable_by?(@staff_user)
    end

    test "staff still require read-access to repository", skip_enterprise: true do
      refute @priv_org_repo_write.code_scanning_readable_by?(@staff_user)
      refute @priv_org_repo_write.code_scanning_writable_by?(@staff_user)
      refute @priv_org_repo_write.code_scanning_analyses_deletable_by?(@staff_user)
    end

    test "staff unlock access" do
      assert @priv_org_repo_write.code_scanning_readable_by?(@staff_unlock_user)
      assert @priv_org_repo_write.code_scanning_writable_by?(@staff_unlock_user)
      # Admin-level FGPs are not open to staff
      refute @priv_org_repo_write.code_scanning_analyses_deletable_by?(@staff_unlock_user)
    end

    test "errors from auth call are logged" do
      Platform::Loaders::Permissions::BatchAuthorize.stubs(:load).returns(Promise.resolve(Authzd::Response.from_error("Test error")))

      # the error should get logged
      Failbot.expects(:report).with do |e, opts|
        opts[:"gh.repo.id"] == @pub_org_repo.id &&
        opts[:"gh.actor.login"] == @owner.login &&
        opts[:"gh.code_scanning.authz_action"] == :read_code_scanning &&
        e.message == "Test error"
      end

      # It should usually succeed for the org owner, but here it won't because of the stubbed error
      refute @pub_org_repo.code_scanning_readable_by?(@owner)
    end
  end

  context "#code_scanning_fgp_permissions" do
    test "fgp_readable user" do
      assert @priv_org_repo_write.code_scanning_readable_by?(@custom_reader_user)
      refute @priv_org_repo_write.code_scanning_readable_by?(@custom_writer_user)
      refute @priv_org_repo_write.code_scanning_readable_by?(@custom_delete_alerts_user)
    end
    test "fgp_readable team" do
      assert @priv_org_repo_write.code_scanning_readable_by?(@reader_team_member)
      refute @priv_org_repo_write.code_scanning_readable_by?(@writer_team_member)
      refute @priv_org_repo_write.code_scanning_readable_by?(@delete_alerts_team_member)
    end
    test "fgp_readable enterprise team" do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      repo.stubs(:code_scanning_usable?).returns(true)
      # helper method enables FF for ETv2
      read_user, read_team = add_user_to_enterprise_team(business: repo.business)
      write_user, write_team = add_user_to_enterprise_team(business: repo.business)
      delete_user, delete_team = add_user_to_enterprise_team(business: repo.business)

      # refute team members have access
      refute repo.code_scanning_readable_by?(read_user)
      refute repo.code_scanning_readable_by?(write_user)
      refute repo.code_scanning_readable_by?(delete_user)

      # grant team member access via ETv2 role
      grant_fgp_to_enterprise_team(team: read_team, target: repo, fgps: [:read_code_scanning])
      grant_fgp_to_enterprise_team(team: write_team, target: repo, fgps: [:write_code_scanning])
      grant_fgp_to_enterprise_team(team: delete_team, target: repo, fgps: [:delete_alerts_code_scanning])

      # @TODO authz-exp fix the authzd policy to allow for Business Team role grants
      # assert repo.code_scanning_readable_by?(read_user)
      refute repo.code_scanning_readable_by?(write_user)
      refute repo.code_scanning_readable_by?(delete_user)
    end
    test "fgp_writable user" do
      assert @priv_org_repo_write.code_scanning_writable_by?(@custom_writer_user)
      refute @priv_org_repo_write.code_scanning_writable_by?(@custom_reader_user)
      refute @priv_org_repo_write.code_scanning_writable_by?(@custom_delete_alerts_user)
    end
    test "fgp_writable team" do
      assert @priv_org_repo_write.code_scanning_writable_by?(@writer_team_member)
      refute @priv_org_repo_write.code_scanning_writable_by?(@reader_team_member)
      refute @priv_org_repo_write.code_scanning_writable_by?(@delete_alerts_team_member)
    end
    test "fgp_writable enterprise team" do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      repo.stubs(:code_scanning_usable?).returns(true)
      # helper method enables FF for ETv2
      read_user, read_team = add_user_to_enterprise_team(business: repo.business)
      write_user, write_team = add_user_to_enterprise_team(business: repo.business)
      delete_user, delete_team = add_user_to_enterprise_team(business: repo.business)

      # refute team member has access
      refute repo.code_scanning_readable_by?(read_user)
      refute repo.code_scanning_readable_by?(write_user)
      refute repo.code_scanning_readable_by?(delete_user)

      # grant team member access via ETv2 role
      grant_fgp_to_enterprise_team(team: read_team, target: repo, fgps: [:read_code_scanning])
      grant_fgp_to_enterprise_team(team: write_team, target: repo, fgps: [:write_code_scanning])
      grant_fgp_to_enterprise_team(team: delete_team, target: repo, fgps: [:delete_alerts_code_scanning])

      # @TODO authz-exp fix the authzd policy to allow for Business Team role grants
      # assert repo.code_scanning_writable_by?(write_user)
      refute repo.code_scanning_writable_by?(read_user)
      refute repo.code_scanning_writable_by?(delete_user)
    end
    test "fgp_delete_analysis user" do
      assert @priv_org_repo_write.code_scanning_analyses_deletable_by?(@custom_delete_alerts_user)
      refute @priv_org_repo_write.code_scanning_analyses_deletable_by?(@custom_reader_user)
      refute @priv_org_repo_write.code_scanning_analyses_deletable_by?(@custom_writer_user)
    end
    test "fgp_delete_analysis team" do
      assert @priv_org_repo_write.code_scanning_analyses_deletable_by?(@delete_alerts_team_member)
      refute @priv_org_repo_write.code_scanning_analyses_deletable_by?(@reader_team_member)
      refute @priv_org_repo_write.code_scanning_analyses_deletable_by?(@writer_team_member)
    end
    test "fgp_delete_analysis enterprise team" do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      repo.stubs(:code_scanning_usable?).returns(true)
      # helper method enables FF for ETv2
      read_user, read_team = add_user_to_enterprise_team(business: repo.business)
      write_user, write_team = add_user_to_enterprise_team(business: repo.business)
      delete_user, delete_team = add_user_to_enterprise_team(business: repo.business)

      # refute team member has access
      refute repo.code_scanning_readable_by?(read_user)
      refute repo.code_scanning_readable_by?(write_user)
      refute repo.code_scanning_readable_by?(delete_user)

      # grant team member access via ETv2 role
      grant_fgp_to_enterprise_team(team: read_team, target: repo, fgps: [:read_code_scanning])
      grant_fgp_to_enterprise_team(team: write_team, target: repo, fgps: [:write_code_scanning])
      grant_fgp_to_enterprise_team(team: delete_team, target: repo, fgps: [:delete_alerts_code_scanning])

      # @TODO authz-exp fix the authzd policy to allow for Business Team role grants
      # assert repo.code_scanning_analyses_deletable_by?(delete_user)
      refute repo.code_scanning_analyses_deletable_by?(read_user)
      refute repo.code_scanning_analyses_deletable_by?(write_user)
    end
  end

  context "'access to alerts' role" do
    test "can read and write alerts" do
      test_user = create(:user)
      @org.add_member(test_user, action: :read)

      refute @priv_org_repo.code_scanning_readable_by?(test_user)
      refute @priv_org_repo.code_scanning_writable_by?(test_user)

      # Add to "Access to alerts" for the repo
      @priv_org_repo.vulnerability_manager.add_authorized_user_or_team(test_user)

      assert @priv_org_repo.code_scanning_readable_by?(test_user)
      assert @priv_org_repo.code_scanning_writable_by?(test_user)
    end

    test "cannot delete alerts" do
      test_user = create(:user)
      @org.add_member(test_user, action: :read)

      refute @priv_org_repo.code_scanning_analyses_deletable_by?(test_user)

      # Add to "Access to alerts" for the repo
      @priv_org_repo.vulnerability_manager.add_authorized_user_or_team(test_user)

      refute @priv_org_repo.code_scanning_analyses_deletable_by?(test_user)
    end

    test "can be inherited from an enterprise team" do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      repo.stubs(:code_scanning_usable?).returns(true)
      team_member, team = add_user_to_enterprise_team(business: repo.business)

      grant_fgp_to_enterprise_team(team: team, target: repo, fgps: [:read_repo_contents])

      # Add to "Access to alerts" for the repo
      repo.vulnerability_manager.add_authorized_user_or_team(team)

      assert repo.code_scanning_readable_by?(team_member)
      assert repo.code_scanning_writable_by?(team_member)
    end
  end

  context "security manager role" do
    test "can read, write, and delete alerts" do
      test_user = create(:user)
      @org.add_member(test_user, action: :read)

      @security_manager_team.add_member test_user
      assert @priv_org_repo.code_scanning_readable_by?(test_user)
      assert @priv_org_repo.code_scanning_writable_by?(test_user)
      assert @priv_org_repo.code_scanning_analyses_deletable_by?(test_user)

      @security_manager_team.remove_member test_user
      refute @priv_org_repo.code_scanning_readable_by?(test_user)
      refute @priv_org_repo.code_scanning_writable_by?(test_user)
      refute @priv_org_repo.code_scanning_analyses_deletable_by?(test_user)
    end
  end
end
