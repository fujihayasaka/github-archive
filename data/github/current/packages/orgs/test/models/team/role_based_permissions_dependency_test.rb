# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamPermissionsDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @org = create(:business_plus_organization)
    @team = create(:public_team, organization: @org)
    @child_team = create(:public_team, organization: @org, parent_team_id: @team.id)
    @repo = create(:repository, :minimal, owner: @org)
    @user = create(:user)

    @org_role_1 = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
    @org_role_2 = create(:custom_organization_role, owner_id: @org.id, owner_type: "Organization")
  end

  context "#async_most_capable_action_or_role_for" do
    test "returns most capable action if no role for repo" do
      assert @team.add_member(@user)
      assert @team.add_repository(@repo, :admin)

      assert_equal "admin", @team.async_most_capable_action_or_role_for(@repo).sync
    end

    test "returns role for repo" do
      assert @team.add_member(@user)
      assert @team.add_repository(@repo, :triage)

      assert_equal "triage", @team.async_most_capable_action_or_role_for(@repo).sync
    end

    test "returns most capable role for repo" do
      child_team = create(:public_team, organization: @org, parent_team_id: @team.id)
      assert @team.add_repository(@repo, :triage)
      create(:user_role, actor: child_team, target: @repo, role: Role.maintain_role)
      assert_equal "maintain", child_team.async_most_capable_action_or_role_for(@repo).sync
    end

    test "returns action if it is more capable than role" do
      child_team = create(:public_team, organization: @org, parent_team_id: @team.id)
      assert @team.add_repository(@repo, :triage)
      child_team.add_repository(@repo, :admin)
      assert_equal "admin", child_team.async_most_capable_action_or_role_for(@repo).sync
    end

    test "include_custom_roles=true, role_priority=true returns custom role" do
      # Members of child_team have two grants on @repo:
      #  * via @team => write
      #  * via child_team => custom role based on write
      #
      # When specifying flags include_custom_roles=true and role_priority=true,
      # #async_most_capable_action_or_role_for should return the name of the
      # custom role.

      role = create_custom_role(owner: @org, base_role: :write)
      child_team = create(:public_team, organization: @org, parent_team_id: @team.id)

      assert @team.add_repository(@repo, role.name)
      assert child_team.add_repository(@repo, :write)
      assert_equal role.name, child_team.async_most_capable_action_or_role_for(@repo, include_custom_roles: true, role_priority: true).sync
    end

    test "include_custom_roles=true, role_priority=false returns base action" do
      # Members of child_team have two grants on @repo:
      #  * via @team => write
      #  * via child_team => custom role based on write
      #
      # When specifying flags include_custom_roles=true and role_priority=false,
      # #async_most_capable_action_or_role_for should return the name of the
      # "write" ability.

      role = create_custom_role(owner: @org, base_role: :write)
      child_team = create(:public_team, organization: @org, parent_team_id: @team.id)

      assert @team.add_repository(@repo, role.name)
      assert child_team.add_repository(@repo, :write)
      assert_equal "write", child_team.async_most_capable_action_or_role_for(@repo, include_custom_roles: true, role_priority: false).sync
    end

    test "include_custom_roles=false, role_priority=true returns base action" do
      # Members of child_team have two grants on @repo:
      #  * via @team => write
      #  * via child_team => custom role based on write
      #
      # When specifying flags include_custom_roles=false and role_priority=true,
      # #async_most_capable_action_or_role_for should return the name of the
      # base role of the custom role (in this case, "write").

      role = create_custom_role(owner: @org, base_role: :write)
      child_team = create(:public_team, organization: @org, parent_team_id: @team.id)

      assert @team.add_repository(@repo, role.name)
      assert child_team.add_repository(@repo, :write)
      assert_equal "write", child_team.async_most_capable_action_or_role_for(@repo, include_custom_roles: false, role_priority: true).sync
    end

    test "include_custom_roles=false, role_priority=false returns base action" do
      # Members of child_team have two grants on @repo:
      #  * via @team => write
      #  * via child_team => custom role based on write
      #
      # When specifying flags include_custom_roles=false and role_priority=false,
      # #async_most_capable_action_or_role_for should return the name of the
      # base role of the custom role (in this case, "write").

      role = create_custom_role(owner: @org, base_role: :write)
      child_team = create(:public_team, organization: @org, parent_team_id: @team.id)

      assert @team.add_repository(@repo, role.name)
      assert child_team.add_repository(@repo, :write)
      assert_equal "write", child_team.async_most_capable_action_or_role_for(@repo, include_custom_roles: false, role_priority: false).sync
    end

    test "directly assigned roles are ranked above equivalent inherited roles" do
      parent_role = create_custom_role(role_name: "parent-role", owner: @org, base_role: :write)
      child_role = create_custom_role(role_name: "child-role", owner: @org, base_role: :write)

      parent_team = create(:public_team, organization: @org)
      child_team = create(:public_team, organization: @org, parent_team_id: parent_team.id)

      # parent role assigned first
      parent_team.add_repository(@repo, parent_role.name)
      child_team.add_repository(@repo, child_role.name)

      result = child_team.async_most_capable_action_or_role_for(@repo, include_custom_roles: true, role_priority: true).sync
      assert_equal child_role.name, result
      assert_equal child_role, @repo.async_most_capable_action_or_role_for(child_team).sync

      # parent role assigned last
      parent_team.remove_repository(@repo)
      child_team.remove_repository(@repo)
      child_team.add_repository(@repo, child_role.name)
      parent_team.add_repository(@repo, parent_role.name)

      result = child_team.async_most_capable_action_or_role_for(@repo, include_custom_roles: true, role_priority: true).sync
      assert_equal child_role.name, result
      assert_equal child_role, @repo.async_most_capable_action_or_role_for(child_team).sync
    end

    test "returns all repo role for repo" do
      assert @org.grant_org_role(assignee: @team, role: OrganizationRole.all_repo_read_role).success?
      result = @team.async_most_capable_action_or_role_for(@repo, include_custom_roles: true, role_priority: true).sync

      assert_equal "read", result
    end

    test "returns all repo role when greater than direct grant" do
      assert @team.add_member(@user)
      assert @team.add_repository(@repo, :read)
      assert @org.grant_org_role(assignee: @team, role: OrganizationRole.all_repo_write_role).success?
      result = @team.async_most_capable_action_or_role_for(@repo, include_custom_roles: false, role_priority: true).sync

      assert_equal "write", result
    end
  end

  context "#async_role_for" do
    test "returns most capable role for repo" do
      assert @team.add_repository(@repo, :triage)
      assert_equal Role.triage_role, @team.async_role_for(@repo).sync
    end

    test "returns inherited most capable role" do
      child_team = create(:public_team, organization: @org, parent_team_id: @team.id)
      assert @team.add_repository(@repo, :triage)
      assert_equal Role.triage_role, child_team.async_role_for(@repo).sync
    end

    test "returns nil if no role" do
      assert_nil @team.async_role_for(@repo).sync
    end

    test "returns custom role" do
      role = create_custom_role(owner: @org, base_role: :write)
      assert @team.add_repository(@repo, role.name)
      assert_equal role, @team.async_role_for(@repo, include_custom_roles: true).sync
    end

    test "returns base role of custom role" do
      role = create_custom_role(owner: @org, base_role: :write)
      assert @team.add_repository(@repo, role.name)
      assert_equal Role.write_role, @team.async_role_for(@repo, include_custom_roles: false).sync
    end

    test "returns base role of all repo role" do
      assert @org.grant_org_role(assignee: @team, role: OrganizationRole.all_repo_maintain_role).success?
      assert_equal Role.maintain_role, @team.async_role_for(@repo, include_custom_roles: false).sync
    end
  end

  context "#org_roles" do
    test "returns direct roles" do
      @org.grant_org_role(assignee: @team, role: @org_role_1)
      @org.grant_org_role(assignee: @team, role: @org_role_2)
      roles = @team.org_roles
      assert_same_elements [@org_role_1, @org_role_2], roles
    end

    test "deduplicates roles" do
      @org.grant_org_role(assignee: @team, role: @org_role_1)
      @org.grant_org_role(assignee: @child_team, role: @org_role_1)
      roles = @child_team.org_roles(include_inherrited: true)

      assert_equal 1, roles.size
    end

    test "batch loads roles" do
      @org.grant_org_role(assignee: @team, role: @org_role_1)
      @org.grant_org_role(assignee: @child_team, role: @org_role_2)

      assert_query_count_per_table({ user_roles: 1, roles: 1 }) do
        GitHub::PrefillAssociations.prefill_batch_method([@team, @child_team], :org_roles)
      end

      assert_query_count 0 do
        assert_same_elements [@org_role_1], @team.org_roles
        assert_same_elements [@org_role_2], @child_team.org_roles
      end
    end
  end

  context "#action_or_role_over_repositories" do
    test "returns direct ability and role for repos" do
      another_repo = create(:repository, :minimal, owner: @org)
      assert @team.add_repository(@repo, :write)
      assert @team.add_repository(another_repo, :triage)
      assert_same_hash({ @repo.id => "Write", another_repo.id => "Triage" }, @team.action_or_role_over_repositories)
    end

    test "returns direct custom roles for repos" do
      custom_role = create_custom_role(owner: @org, role_name: "my CUSTOM role")

      assert @team.add_repository(@repo, custom_role.name.to_sym)
      assert_same_hash({ @repo.id => custom_role.display_name }, @team.action_or_role_over_repositories)
    end

    test "returns indirect ability and role for repos" do
      child_team = create(:team, organization: @org, parent_team_id: @team.id, privacy: :closed)
      another_repo = create(:repository, :minimal, owner: @org)
      assert @team.add_repository(@repo, :write)
      assert @team.add_repository(another_repo, :triage)
      assert_same_hash({ @repo.id => "Write", another_repo.id => "Triage" }, child_team.action_or_role_over_repositories)
    end

    test "returns indirect custom roles for repos" do
      custom_role = create_custom_role(owner: @org, role_name: "indirect custom Role")
      child_team = create(:team, organization: @org, parent_team_id: @team.id, privacy: :closed)

      assert @team.add_repository(@repo, custom_role.name.to_sym)
      assert_same_hash({ @repo.id => custom_role.display_name }, child_team.action_or_role_over_repositories)
    end

    test "returns most capable ability and role for repos" do
      child_team = create(:team, organization: @org, parent_team_id: @team.id, privacy: :closed)
      another_repo = create(:repository, :minimal, owner: @org)
      assert @team.add_repository(@repo, :write)
      assert child_team.add_repository(@repo, :maintain)
      assert @team.add_repository(another_repo, :triage)
      assert child_team.add_repository(another_repo, :write)
      assert_same_hash({ @repo.id => "Maintain", another_repo.id => "Write" }, child_team.action_or_role_over_repositories)
    end

    test "returns most capable custom roles for repos" do
      custom_role = create_custom_role(owner: @org, base_role: :maintain, role_name: "custom role base Maintain")
      child_team = create(:team, organization: @org, parent_team_id: @team.id, privacy: :closed)

      assert @team.add_repository(@repo, :maintain)
      assert child_team.add_repository(@repo, custom_role.name.to_sym)
      assert_same_hash({ @repo.id => custom_role.display_name }, child_team.action_or_role_over_repositories)
    end
  end
end
