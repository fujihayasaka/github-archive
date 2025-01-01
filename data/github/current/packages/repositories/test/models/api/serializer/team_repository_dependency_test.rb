# typed: false
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class TeamRepoSerializersTest < Api::SerializerTestCase
  include PageHelper
  include FineGrainedPermissionsTestHelper

  fixtures do
    @owner = create :paid_user, login: "owner"

    @org_admin = create :user, plan: "medium"
    @org   = create :organization, admin: @org_admin

    @rando = create(:user)

    @repo = create :repository, owner: @owner, name: "Kunze-Smith", from_example: :simple

    @priv_repo = create :private_repository, owner: @owner, from_example: :simple

    @disabled_repo = create :repository, owner: @owner
    staff = create(:staff_admin_user)
    @disabled_repo.access.disable("size", staff)

    @submodule_repo = create(:repository, name: "tree_with_submod", owner: @owner, from_example: :tree_with_submod)

    @org_repo = create :repository, owner: @org

    @forked_repo = create(:fork_repository, forker: @rando, fork_repo: @repo)

    @invitation = create(:repository_invitation,
      invitee: @rando,
      inviter: @owner,
      repository: @priv_repo,
      permissions: 1,
    )

    @commit_comment = @repo.commit_comments.create commit_id: @repo.default_oid, body: "foo", user: @owner
    @page = create :page, owner: @owner
    @build = Page::Build.create! page: @page, pusher_id: @owner.id, status: "built", commit: "abc"
  end

  setup do
    @org_repo_interactions = RepositoryInteractionAbility.new(@org_repo)

    @tree_object = TreeEntry.new(@repo, {
      "type" => "tree",
      "oid"  => @repo.heads["master"].commit.tree_oid,
      "path" => "",
    })
  end

  context "#team_repository_hash" do
    test "for a team with 'pull' access to the repo" do
      org = create(:organization)
      repo = create :private_repository, owner: org
      team = create(:team, organization: org)
      team.add_repository repo, :pull

      #team_repo is actually team_repo_hash
      #it relies on method_missing
      #see /test/models/api/helper.rb#L26
      output = team_repo(repo, { team: team })

      assert_equal({ "pull" => true, "triage" => false, "push" => false, "maintain" => false, "admin" => false }, output["permissions"])
      assert_equal "read", output["role_name"]
      assert_able team, :read, repo
      refute_able team, :write, repo
    end

    test "for a team with 'push' access to the repo" do
      org = create(:organization)
      repo = create :private_repository, owner: org
      team = create(:team, organization: org)
      team.add_repository repo, :push

      output = team_repo(repo, { team: team })

      assert_equal({ "pull" => true, "triage" => true, "push" => true, "maintain" => false, "admin" => false }, output["permissions"])
      assert_equal "write", output["role_name"]
      assert_able team, :write, repo
      refute_able team, :admin, repo
    end

    test "for a child team with 'push' access to the repo" do
      org = create(:organization)
      repo = create :private_repository, owner: org
      parent_team = create(:public_team, organization: org, name: "parent")
      parent_team.add_repository repo, :push
      child_team = create(:public_team, organization: org, parent_team: parent_team, name: "child")

      output = team_repo(repo, { team: child_team })

      assert_equal({ "pull" => true, "triage" => true, "push" => true, "maintain" => false, "admin" => false }, output["permissions"])
      assert_equal "write", output["role_name"]

      assert_able parent_team, :write, repo
      refute_able parent_team, :admin, repo
    end

    test "for a team with 'admin' access to the repo" do
      org = create(:organization)
      repo = create :private_repository, owner: org
      team = create(:team, organization: org)
      team.add_repository repo, :admin

      output = team_repo(repo, { team: team })

      assert_equal({ "pull" => true, "triage" => true, "push" => true, "maintain" => true, "admin" => true }, output["permissions"])
      assert_equal "admin", output["role_name"]
      assert_able team, :admin, repo
    end

    test "for a team with a custom role access to the repo" do
      org = create(:business_plus_org)
      repo = create :private_repository, owner: org
      team = create(:team, organization: org)
      custom_role = create_custom_role(owner: org, base_role: :maintain)
      team.add_repository(repo, custom_role.name)

      output = team_repo(repo, { team: team })

      assert_equal({ "pull" => true, "triage" => true, "push" => true, "maintain" => true, "admin" => false }, output["permissions"])
      assert_equal custom_role.name, output["role_name"]
      assert_able team, :write, repo
      refute_able team, :admin, repo
    end

    test "gracefully handles nil simple_repository_hash when missing a network" do
      repo = create :private_repository
      repo.stubs(:network).returns(nil)
      assert_nil team_repo(repo)
    end

  end
end

class TeamRepoSerializersMultiTenantTest < Api::SerializerTestCase
  fixtures do
    on_multi_tenant_enterprise do
      @owner = create :emu
      @business = @owner.enterprise_managed_business
      @org = create :organization, business: @business, admin: @owner
      @repo = create :repository, organization: @org
      @team = create(:team, organization: @org)
      @team.add_repository @repo, :push
    end
  end

  setup do
    on_multi_tenant_enterprise(tenant: @business)
  end

  context "#team_repo_hash" do
    test "returns url with display login value for external calls" do
      output = output = team_repo(@repo, { team: @team })

      refute_equal @repo.name_with_owner, @repo.name_with_display_owner
      assert_includes output["url"], @repo.name_with_display_owner

      refute_includes output["git_url"], @repo.name_with_owner
      refute_includes output["ssh_url"], @repo.name_with_owner
      refute_includes output["clone_url"], @repo.name_with_owner
      refute_includes output["svn_url"], @repo.name_with_owner

      assert_includes output["git_url"], @repo.name_with_display_owner
      assert_includes output["ssh_url"], @repo.name_with_display_owner
      assert_includes output["clone_url"], @repo.name_with_display_owner
      assert_includes output["svn_url"], @repo.name_with_display_owner
    end

    test "returns url with unique login value for internal calls without serialize login option" do
      GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)

      output = output = team_repo(@repo, { team: @team })

      refute_equal @repo.name_with_owner, @repo.name_with_display_owner
      assert_includes output["url"], @repo.name_with_owner
      assert_includes output["git_url"], @repo.name_with_owner
      assert_includes output["ssh_url"], @repo.name_with_owner
      assert_includes output["clone_url"], @repo.name_with_owner
      assert_includes output["svn_url"], @repo.name_with_owner
    end

    test "returns url with display login value for internal calls with serialize login set to display" do
      GitHub.stubs(:proxima_internal_api_unique_logins_required?).returns(true)

      output = output = team_repo(@repo, { team: @team, serialize_login: :display })

      refute_equal @repo.name_with_owner, @repo.name_with_display_owner
      assert_includes output["url"], @repo.name_with_display_owner

      refute_includes output["git_url"], @repo.name_with_owner
      refute_includes output["ssh_url"], @repo.name_with_owner
      refute_includes output["clone_url"], @repo.name_with_owner
      refute_includes output["svn_url"], @repo.name_with_owner

      assert_includes output["git_url"], @repo.name_with_display_owner
      assert_includes output["ssh_url"], @repo.name_with_display_owner
      assert_includes output["clone_url"], @repo.name_with_display_owner
      assert_includes output["svn_url"], @repo.name_with_display_owner
    end
  end
end unless GitHub.single_business_environment?
