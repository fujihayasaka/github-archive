# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryFgpDependencyTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @user = @maintain_user = create :user
    @member = create(:user)
    @owner = create(:user)
    @org_on_business_plus = create(:business_plus_organization, admin: @owner)
    @org_repo = create :repository, :minimal, owner: @org_on_business_plus
    @org_repo.add_member(@maintain_user)
    @team = create(:team, organization: @org_on_business_plus)
    @org_on_business_plus.add_member(@member)

    @other_user = create :user
    @repo_owner = create :user
    @user_repo = create :repository, :minimal, owner: @repo_owner
  end

  context "#async_can_read_resource?" do
    test "returns true for user with read role" do
      assert @org_repo.async_can_read_resource?(@maintain_user, "contents").sync
    end

    test "emu_vss_business flag does not affect behavior for non-emu businesses", skip_enterprise: true do
      # Using internal repositories to test this behavior because unaffiliated members should not have read access
      # For an emu business with the emu_vss_business flag set to true, unaffiliated members will have read access
      business = create(:business)
      org = create(:organization, business: business)
      internal_repo = create(:internal_repository, owner: org)
      unaffiliated_member = create(:user)
      business.add_user_accounts([unaffiliated_member.id])
      refute internal_repo.async_can_read_resource?(unaffiliated_member, "contents").sync
    end

    test "returns true for an enterprise team with a read role" do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      # helper method enables FF for ETv2
      _, team = add_user_to_enterprise_team(business: repo.business)

      # refute team has access
      refute repo.async_can_read_resource?(team, "contents").sync

      # grant team access via ETv2 role
      # base role assigns read_repo_contents
      grant_fgp_to_enterprise_team(team: team, target: repo, fgps: [])

      # this check runs through authzd
      assert repo.async_can_read_resource?(team, "contents").sync
    end

    test "returns true for a member of an enterprise team with a read role" do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      # helper method enables FF for ETv2
      team_member, team = add_user_to_enterprise_team(business: repo.business)

      # refute team member has access
      refute repo.async_can_read_resource?(team_member, "contents").sync

      # grant team member access via ETv2 role
      # base role assigns read_repo_contents
      grant_fgp_to_enterprise_team(team: team, target: repo, fgps: [])

      # this check runs through authzd
      assert repo.async_can_read_resource?(team_member, "contents").sync
    end
  end

  context "#async_can_write_resource?" do
    test "returns true for an enterprise team with a write role" do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      # helper method enables FF for ETv2
      _, team = add_user_to_enterprise_team(business: repo.business)

      # refute team has access
      refute repo.async_can_write_resource?(team, "contents").sync

      # grant team access via ETv2 role
      # base role assigns write_repo_contents
      grant_fgp_to_enterprise_team(team: team, target: repo, fgps: [], base_role: "write")

      # this check runs through authzd
      assert repo.async_can_write_resource?(team, "contents").sync
    end

    test "returns true for a member of an enterprise team with a write role" do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      # helper method enables FF for ETv2
      team_member, team = add_user_to_enterprise_team(business: repo.business)

      # refute team member has access
      refute repo.async_can_write_resource?(team_member, "contents").sync

      # grant team access via ETv2 role
      # base role assigns write_repo_contents
      grant_fgp_to_enterprise_team(team: team, target: repo, fgps: [], base_role: "write")

      # this check runs through authzd
      assert repo.async_can_write_resource?(team_member, "contents").sync
    end
  end

  context "toggle pages settings" do
    test "true for user with maintain role" do
      @org_repo.update_member(@maintain_user, action: :maintain)
      assert @org_repo.async_can_toggle_page_settings?(@maintain_user).sync
    end

    test "true for custom role with corresponding FGP" do
      grant_custom_role(user: @other_user, target: @org_repo, fgps: [:manage_settings_pages])
      assert @org_repo.async_can_toggle_page_settings?(@other_user).sync
    end

    test "true for repo owner" do
      assert @org_repo.async_can_toggle_page_settings?(@org_repo.owner.admin).sync
    end

    test "returns false for a random user" do
      refute @org_repo.async_can_toggle_page_settings?(create(:user)).sync
    end

    test "returns false if actor is not present" do
      refute @org_repo.async_can_toggle_page_settings?(nil).sync
    end
  end

  context "toggle merge settings" do
    test "true for user with maintain role" do
      @org_repo.update_member(@maintain_user, action: :maintain)

      assert @org_repo.async_can_toggle_merge_settings?(@maintain_user).sync
    end

    test "true for custom role with corresponding FGP" do
      grant_custom_role(user: @other_user, target: @org_repo, fgps: [:manage_settings_merge_types])
      assert @org_repo.async_can_toggle_merge_settings?(@other_user).sync
    end

    test "true for repo owner" do
      assert @org_repo.async_can_toggle_merge_settings?(@org_repo.owner.admin).sync
    end

    test "returns false for a random user" do
      refute @org_repo.async_can_toggle_merge_settings?(create(:user)).sync
    end

    test "returns false if actor is not present" do
      refute @org_repo.async_can_toggle_merge_settings?(nil).sync
    end
  end

  context "set social preview" do
    test "true for user with maintain role" do
      @org_repo.update_member(@maintain_user, action: :maintain)

      assert @org_repo.async_can_set_social_preview?(@maintain_user).sync
    end

    test "true for custom role with coresponding FGP" do
      grant_custom_role(user: @other_user, target: @org_repo, fgps: [:set_social_preview])
      assert @org_repo.async_can_set_social_preview?(@other_user).sync
    end

    test "true for repo owner" do
      assert @org_repo.async_can_set_social_preview?(@org_repo.owner.admin).sync
    end

    test "returns false for a random user" do
      refute @org_repo.async_can_set_social_preview?(create(:user)).sync
    end

    test "returns false if actor is not present" do
      refute @org_repo.async_can_set_social_preview?(nil).sync
    end
  end

  context "set interaction limits" do
    test "true for user with maintain role" do
      @org_repo.update_member(@maintain_user, action: :maintain)

      assert @org_repo.async_can_set_interaction_limits?(@maintain_user).sync
    end

    test "true for custom role with coresponding FGP" do
      grant_custom_role(user: @other_user, target: @org_repo, fgps: [:set_interaction_limits])
      assert @org_repo.async_can_set_interaction_limits?(@other_user).sync
    end

    test "true for org admin" do
      assert @org_repo.async_can_set_interaction_limits?(@org_repo.owner.admin).sync
    end

    if GitHub.interaction_limits_enabled?
      test "true for user moderator" do
        @org_on_business_plus.moderation.add_moderator(@member, actor: @owner)
        refute @org_on_business_plus.adminable_by?(@member)
        assert @org_on_business_plus.moderator?(@member)

        assert @org_repo.can_set_interaction_limits?(@member)
        assert @org_repo.async_can_set_interaction_limits?(@member).sync
      end

      test "true for moderator via team" do
        @team.add_member(@member)
        assert @team.member?(@member)
        @org_on_business_plus.moderation.add_moderator(@team, actor: @owner)
        refute @org_on_business_plus.adminable_by?(@member)
        assert @org_on_business_plus.moderator?(@member)

        assert @org_repo.can_set_interaction_limits?(@member)
        assert @org_repo.async_can_set_interaction_limits?(@member).sync
      end

      test "false for moderator on private repo" do
        @org_on_business_plus.moderation.add_moderator(@member, actor: @owner)
        refute @org_on_business_plus.adminable_by?(@member)
        assert @org_on_business_plus.moderator?(@member)
        priv_repo = create(:private_repository, :minimal, owner: @org_on_business_plus)

        refute priv_repo.can_set_interaction_limits?(@member)
        refute priv_repo.async_can_set_interaction_limits?(@member).sync
      end
    end

    test "returns false for a random user" do
      refute @org_repo.async_can_set_interaction_limits?(create(:user)).sync
    end

    test "returns false if actor is not present" do
      refute @org_repo.async_can_set_interaction_limits?(nil).sync
    end
  end

  context "manage deploy keys" do
    test "true for repository admin" do
      repo_admin = create(:user)
      @org_repo.add_member(repo_admin, action: :admin)
      assert @org_repo.async_can_manage_deploy_keys?(repo_admin).sync
    end

    test "true for org admin" do
      assert @org_repo.async_can_manage_deploy_keys?(@org_repo.owner.admin).sync
    end

    test "returns false for a random user" do
      refute @org_repo.async_can_manage_deploy_keys?(create(:user)).sync
    end

    test "returns false for user with write on repo" do
      repo_writer = create(:user)
      @org_repo.add_member(repo_writer, action: :write)
      refute @org_repo.async_can_manage_deploy_keys?(repo_writer).sync
    end
  end

  context "manage webhooks" do
    test "true for user with admin role" do
      @org_repo.update_member(@user, action: :admin)
      assert @org_repo.async_can_manage_webhooks?(@user).sync
    end

    test "false for user with maintain role" do
      @org_repo.update_member(@user, action: :maintain)
      refute @org_repo.async_can_manage_webhooks?(@user).sync
    end

    test "false for user with write role" do
      @org_repo.update_member(@user, action: :write)
      refute @org_repo.async_can_manage_webhooks?(@user).sync
    end

    test "false for user with triage role" do
      @org_repo.update_member(@user, action: :triage)
      refute @org_repo.async_can_manage_webhooks?(@user).sync
    end

    test "false for user with read role" do
      @org_repo.update_member(@user, action: :read)
      refute @org_repo.async_can_manage_webhooks?(@user).sync
    end

    test "true for repo owner" do
      assert @org_repo.async_can_manage_webhooks?(@org_repo.owner.admin).sync
    end

    test "false for a random user" do
      refute @org_repo.async_can_manage_webhooks?(create(:user)).sync
    end

    test "false if user is anonymous" do
      refute @org_repo.async_can_manage_webhooks?(nil).sync
    end

    test "true for custom role with corresponding FGP" do
      grant_custom_role(user: @other_user, target: @org_repo, fgps: [:manage_webhooks])
      assert @org_repo.async_can_manage_webhooks?(@other_user).sync
    end

    test "false for custom role with another FGP" do
      grant_custom_role(user: @other_user, target: @org_repo, fgps: [:set_interaction_limits])
      refute @org_repo.async_can_manage_webhooks?(@other_user).sync
    end

    test "true for team with corresponding FGP" do
      @team.add_member @other_user
      grant_custom_role(user: @team, target: @org_repo, fgps: [:manage_webhooks])
      assert @org_repo.async_can_manage_webhooks?(@other_user).sync
    end

    test "false for team with another FGP" do
      @team.add_member @other_user
      grant_custom_role(user: @team, target: @org_repo, fgps: [:set_interaction_limits])
      refute @org_repo.async_can_manage_webhooks?(@other_user).sync
    end

    test "true for a user with staff unlock on the repo" do
      staff = create(:staff_admin_user, :verified, stafftools_roles: ["can-unlock-repos-with-owners-permission"])
      create :staff_access_grant, accessible: @org_repo, granted_by: @org_repo.owner
      staff.unlock_repository(@org_repo, "hi")
      assert @org_repo.async_can_manage_webhooks?(staff).sync
    end

    test "false for site admin" do
      site_admin = create(:staff_admin_user)
      assert site_admin.site_admin?
      refute @org_repo.async_can_manage_webhooks?(site_admin).sync
    end
  end

  context "#can_manage_topics?" do
    test "returns false for rando" do
      refute @user_repo.can_manage_topics?(@maintain_user)
    end

    test "returns false for org member with write access" do
      @org_on_business_plus.add_member(@other_user, action: :write)

      refute @org_repo.can_manage_topics?(@other_user)
    end

    test "returns true for team with maintainer role" do
      @team.add_member @other_user
      @team.add_repository(@org_repo, :maintain)
      assert @org_repo.can_manage_topics?(@other_user)
    end

    test "returns true for org member with maintainer role" do
      @org_repo.add_member(@other_user, action: :maintain)
      assert @org_repo.can_manage_topics?(@other_user)
    end

    test "returns true when repository owner" do
      assert @user_repo.can_manage_topics?(@repo_owner)
    end

    test "returns true for org admin" do
      @org_on_business_plus.add_member(@other_user, action: :admin)

      assert @org_repo.can_manage_topics?(@other_user)
    end

    test "returns true for installation installed on all repos" do
      user_with_installation = create(:user)
      repo_with_installation = create :repository, :minimal, owner: user_with_installation

      installation = make_integration_installation(
        target: user_with_installation,
        permissions: {
          "administration" => :write
        }
      )
      assert repo_with_installation.can_manage_topics?(installation.bot)
    end

    test "returns false for installation not installed for repo target" do
      user_with_installation = create(:user)
      repo_with_installation = create :repository, :minimal, owner: user_with_installation

      random_user = create(:user)
      random_user_repo = create :repository, :minimal, owner: random_user

      installation = make_integration_installation(
        target: user_with_installation,
        permissions: {
          "administration" => :write
        }
      )
      refute random_user_repo.can_manage_topics?(installation.bot)
    end

    test "returns false when no user is provided" do
      Platform::Loaders::Permissions::BatchAuthorize.expects(:load).never
      refute @org_repo.can_manage_topics?(nil)
    end

    test "returns true for an enterprise team via org base permission" do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      org = repo.owner
      business = org.business

      # helper method enables FF for ETv2
      all_org_team_member, all_org_team = add_user_to_enterprise_team(business: repo.business)
      #
      select_org_team = create(:business_team, business: business, organization_selection_type: :selected)
      _business_org_team_assignment = BusinessTeamOrgAssignment.create!(business_team: select_org_team, organization: org)
      select_org_team_member = create :user
      create(:business_user_account, user: select_org_team_member, business: business)
      select_org_team.add_member(select_org_team_member, caller_type: :business_team)
      #
      unselected_biz_team = create(:business_team, business: business, organization_selection_type: :selected)
      unselected_biz_team_member = create :user
      create(:business_user_account, user: unselected_biz_team_member, business: business)
      unselected_biz_team.add_member(unselected_biz_team_member, caller_type: :business_team)

      # ensure there are no permissions that mask the intent of the test
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { org.update_default_repository_permission(:none, actor: org.admins.first) }
      refute repo.can_manage_topics?(all_org_team_member)
      refute repo.can_manage_topics?(select_org_team_member)
      refute repo.can_manage_topics?(unselected_biz_team_member)

      #
      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { org.update_default_repository_permission(:admin, actor: org.admins.first) }
      assert repo.can_manage_topics?(all_org_team_member)
      assert repo.can_manage_topics?(select_org_team_member)
      refute repo.can_manage_topics?(unselected_biz_team_member)
    end
  end

  context "#can_edit_repo_metadata?" do
    test "returns true when repository owner" do
      assert @user_repo.can_edit_repo_metadata?(@repo_owner)
    end

    test "returns true for org admin" do
      assert @org_repo.can_edit_repo_metadata?(@org_on_business_plus.admin)
    end

    test "returns false for rando" do
      refute @user_repo.can_edit_repo_metadata?(@other_user)
    end

    test "returns false when no user is provided" do
      ::Permissions::Enforcer.expects(:authorize).never
      refute @org_repo.can_edit_repo_metadata?(nil)
    end

    test "returns false for team w/write access" do
      @team.add_member @other_user

      refute @org_repo.can_edit_repo_metadata?(@other_user)
    end

    test "returns false for org member with write access" do
      @org_on_business_plus.add_member(@other_user, action: :write)

      refute @org_repo.can_edit_repo_metadata?(@other_user)
    end

    test "returns true for team with maintainer role" do
      @team.add_member @other_user
      @team.add_repository(@org_repo, :maintain)

      assert @org_repo.can_edit_repo_metadata?(@other_user)
    end

    test "returns true for org member with maintainer role" do
      @org_repo.add_member(@other_user, action: :maintain)
      assert @org_repo.can_edit_repo_metadata?(@other_user)
    end

    test "returns false for an enterprise team with a maintainer role" do
      disable_feature_flag(:report_authzd_indeterminates) # this test fails when authzd raises errors
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      # helper method enables FF for ETv2
      _, team = add_user_to_enterprise_team(business: repo.business)

      # grant team maintain role
      grant_custom_role(user: team, target: repo, base_role: :maintain)

      # this check runs through authzd
      refute repo.can_edit_repo_metadata?(team)
    end

    test "returns true for a member of an enterprise team with a maintainer role", feature_enabled: :enterprise_teams_attributes_include_business_teams do
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      # helper method enables FF for ETv2
      team_member, team = add_user_to_enterprise_team(business: repo.business)

      # refute team member has access
      refute repo.can_edit_repo_metadata?(team_member)

      # grant team maintain role
      grant_custom_role(user: team, target: repo, base_role: :maintain)

      # this check runs through authzd
      assert repo.can_edit_repo_metadata?(team_member)
    end

    test "returns true for a member of an enterprise team with a maintainer role", feature_disabled: :enterprise_teams_attributes_include_business_teams do
      disable_feature_flag(:enterprise_teams_attributes_include_business_teams)
      repo = create(:private_repository, :minimal, owner: create(:enterprise_linked_organization))
      # helper method enables FF for ETv2
      team_member, team = add_user_to_enterprise_team(business: repo.business)

      # refute team member has access
      refute repo.can_edit_repo_metadata?(team_member)

      # grant team maintain role
      grant_custom_role(user: team, target: repo, base_role: :maintain)

      # this check runs through authzd
      refute repo.can_edit_repo_metadata?(team_member)
    end
  end

  context "#can_toggle_wiki?" do
    test "returns true for an admin" do
      assert @org_repo.can_toggle_wiki?(@org_repo.owner.admin)
    end

    test "returns true for a maintainer" do
      @org_repo.update_member(@maintain_user, action: :maintain)
      assert @org_repo.can_toggle_wiki?(@maintain_user)
    end

    test "returns false for a random user" do
      refute @org_repo.can_toggle_wiki?(create(:user))
    end
  end

  context "#async_can_toggle_projects?" do
    test "returns true for an admin" do
      assert @org_repo.async_can_toggle_projects?(@org_repo.owner.admin).sync
    end

    test "returns true for a maintainer" do
      @org_repo.update_member(@maintain_user, action: :maintain)
      assert @org_repo.async_can_toggle_projects?(@maintain_user).sync
    end

    test "returns false for a random user" do
      refute @org_repo.async_can_toggle_projects?(create(:user)).sync
    end

    test "returns false if actor is not present" do
      refute @org_repo.async_can_toggle_projects?(nil).sync
    end
  end

  context "one or more permissions that enables managing reposistory settings" do
    test "returns true for role with one or more repo setting options" do
      @org_repo.update_member(@maintain_user, action: :maintain)
      assert @org_repo.async_can_view_repository_settings?(@maintain_user).sync
    end

    test "returns true for custom role with at least one of the FGPs" do
      user = create(:user)
      grant_custom_role(user: user, target: @org_repo, fgps: [:set_interaction_limits])
      assert @org_repo.async_can_view_repository_settings?(user).sync
    end

    test "returns true for public repo if user only has FGP available for public repo" do
      user = create(:user)
      grant_custom_role(user: user, target: @org_repo, fgps: [:set_interaction_limits])
      assert @org_repo.async_can_view_repository_settings?(user).sync
    end

    test "returns false for unrelated FGP" do
      user = create(:user)
      grant_custom_role(user: user, target: @org_repo, fgps: [:add_label])
      refute @org_repo.async_can_view_repository_settings?(user).sync
    end

    test "return false for write permissions" do
      @org_repo.update_member(@maintain_user, action: :write)
      refute @org_repo.async_can_view_repository_settings?(@maintain_user).sync
    end

    test "returns false for private repo if user only has FGP available for public repo" do
      user = create(:user)
      private_repo = create(:private_repository, :minimal, owner: @org_on_business_plus)
      grant_custom_role(user: user, target: private_repo, fgps: [:set_interaction_limits])
      refute private_repo.async_can_view_repository_settings?(user).sync
    end
  end

  context "#can_read_interaction_limits?" do
    test "returns true for repo admin" do
      assert @org_repo.can_read_interaction_limits?(@org_repo.owner.admin)
    end

    test "returns true for maintain user" do
      @org_repo.update_member(@maintain_user, action: :maintain)
      assert @org_repo.can_read_interaction_limits?(@maintain_user)
    end

    test "returns false for random user" do
      refute @org_repo.can_read_interaction_limits?(create(:user))
    end

    test "returns false for nil actor" do
      refute @org_repo.can_read_interaction_limits?(nil)
    end
  end

  context "#async_can_edit_announcement_banners?" do
    test "returns true for repo admin" do
      @org_repo.update_member(@maintain_user, action: :admin)
      assert @org_repo.async_can_edit_announcement_banners?(@maintain_user).sync
    end

    test "returns true for maintainer" do
      @org_repo.update_member(@maintain_user, action: :maintain)
      assert @org_repo.async_can_edit_announcement_banners?(@maintain_user).sync
    end

    test "returns true for user with edit_repo_announcement_banners FGP" do
      user = create(:user)
      refute @org_repo.async_can_edit_announcement_banners?(user).sync

      grant_custom_role(user: user, target: @org_repo, fgps: [:edit_repo_announcement_banners])
      assert @org_repo.async_can_edit_announcement_banners?(user).sync
    end

    test "returns false for writer" do
      @org_repo.update_member(@maintain_user, action: :write)
      refute @org_repo.async_can_edit_announcement_banners?(@maintain_user).sync
    end

    test "returns false for reader" do
      @org_repo.update_member(@maintain_user, action: :read)
      refute @org_repo.async_can_edit_announcement_banners?(@maintain_user).sync
    end

    test "returns false for random user" do
      refute @org_repo.async_can_edit_announcement_banners?(create(:user)).sync
    end

    test "returns false for nil actor" do
      refute @org_repo.async_can_edit_announcement_banners?(nil).sync
    end
  end

  context "#async_can_edit_custom_property_values_as_repo_actor?" do
    test "returns true for repo admin" do
      @org_repo.update_member(@maintain_user, action: :admin)
      assert @org_repo.async_can_edit_custom_property_values_as_repo_actor?(@maintain_user).sync
    end

    test "returns false for maintainer" do
      @org_repo.update_member(@maintain_user, action: :maintain)
      refute @org_repo.async_can_edit_custom_property_values_as_repo_actor?(@maintain_user).sync
    end

    test "returns true for user with edit_repo_custom_properties_values FGP" do
      user = create(:user)
      grant_custom_role(user: user, target: @org_repo, fgps: [:edit_repo_custom_properties_values])
      assert @org_repo.async_can_edit_custom_property_values_as_repo_actor?(user).sync
    end

    test "returns false for user with edit_org_custom_properties_values FGP" do
      user = create(:user)
      grant_custom_org_role(user: user, target: @org_on_business_plus, fgps: [:edit_org_custom_properties_values])
      refute @org_repo.async_can_edit_custom_property_values_as_repo_actor?(user).sync
    end

    test "returns false for random user" do
      refute @org_repo.async_can_edit_custom_property_values_as_repo_actor?(create(:user)).sync
    end

    test "returns false for nil actor" do
      refute @org_repo.async_can_edit_custom_property_values_as_repo_actor?(nil).sync
    end
  end
end
