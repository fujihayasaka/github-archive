# typed: true
# frozen_string_literal: true

require "test_helper"

class UserOrganizationsDependencyTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @viewer = create(:user)
  end

  context "#organization_ids_by_member_or_billing_manager_status" do
    test "loads orgs the user belongs to or acts as billing manager of" do
      @org.add_member(@user)

      billing_managed_org = create(:organization)
      billing_managed_org.billing.add_manager(@user, actor: billing_managed_org.admins.first)

      # Org admins are still members of their org:
      admined_org = create(:organization, admin: @user)

      unrelated_org = create(:organization)

      result = @user.organization_ids_by_member_or_billing_manager_status

      assert_instance_of Hash, result
      assert_same_elements [:member, :billing_manager], result.keys
      assert_equal [@org.id, admined_org.id].to_set, result[:member]
      assert_equal [billing_managed_org.id].to_set, result[:billing_manager]
    end

    test "returns empty sets when user is neither a member nor billing manager of any org" do
      result = @user.organization_ids_by_member_or_billing_manager_status
      assert_equal({ member: Set.new, billing_manager: Set.new }, result)
    end

    test "returns IDs of orgs user belongs to and an empty set when they aren't a billing manager of any org" do
      @org.add_member(@user)
      result = @user.organization_ids_by_member_or_billing_manager_status
      assert_equal({ member: Set.new([@org.id]), billing_manager: Set.new }, result)
    end

    test "returns IDs of orgs user is billing manager of and an empty set when they don't belong to any org" do
      @org.billing.add_manager(@user, actor: @org.admins.first)
      result = @user.organization_ids_by_member_or_billing_manager_status
      assert_equal({ member: Set.new, billing_manager: Set.new([@org.id]) }, result)
    end
  end

  context "#newest_organization" do
    test "returns nil when user does not belong to any organizations" do
      assert_nil @user.newest_organization
    end

    test "returns nil when user only belongs to soft-delete organization" do
      soft_deleted_org = create :organization, login: "soft-deleted-org"
      soft_deleted_org.soft_delete!

      assert_nil @user.newest_organization
    end

    test "returns the most recent organization the user was added to" do
      some_org = create(:organization)

      some_org.add_member(@user)
      assert_equal some_org, @user.newest_organization,
        "should return only org user has been added to"

      @org.add_member(@user)
      assert_equal @org, @user.newest_organization,
        "should return the org the user was most recently added to"

      assert_equal @org, @user.newest_organization,
        "should continue to return the same org the user was last added to"
    end

    test "returns the next most recent organization the user was added to if the most recent has been soft-deleted" do
      @org.add_member(@user)
      soft_deleted_org = create :organization, login: "soft-deleted-org"
      soft_deleted_org.add_member(@user)
      soft_deleted_org.soft_delete!

      assert_equal @org, @user.newest_organization
    end
  end

  context "#member_or_billing_manager_organizations" do
    test "returns orgs that the given user is a member or billing manager of" do
      member_org = @org
      member_org.add_member(@user)
      owned_org = create(:organization, admin: @user)
      billing_manager_org = create(:organization)
      billing_manager_org.billing.add_manager(@user, actor: billing_manager_org.admin)
      unrelated_org = create(:organization)

      result = @user.member_or_billing_manager_organizations

      assert_includes result, owned_org
      assert_includes result, billing_manager_org
      assert_includes result, member_org
      refute_includes result, unrelated_org
    end

    test "does not return soft-deleted orgs", skip_enterprise: true do
      member_org = @org
      member_org.add_member(@user)
      owned_org = create(:organization, admin: @user)
      billing_manager_org = create(:organization)
      billing_manager_org.billing.add_manager(@user, actor: billing_manager_org.admin)
      unrelated_org = create(:organization)

      member_org.soft_delete!

      result = @user.member_or_billing_manager_organizations
      assert_same_elements [owned_org, billing_manager_org], result
    end
  end

  context "#owned_or_billing_manager_organizations" do
    test "returns orgs that the given user is owner or billing manager of" do
      member_org = @org
      member_org.add_member(@user)
      owned_org = create(:organization, admin: @user)
      billing_manager_org = create(:organization)
      billing_manager_org.billing.add_manager(@user, actor: billing_manager_org.admin)
      unrelated_org = create(:organization)

      result = @user.owned_or_billing_manager_organizations

      assert_includes result, owned_org
      assert_includes result, billing_manager_org
      refute_includes result, member_org
      refute_includes result, unrelated_org
    end

    test "includes organizations that the user is an owner of" do
      user = create(:user)

      org = create(:organization)
      org.add_member user, action: :admin
      assert org.adminable_by?(user)

      other_org = create(:organization)
      other_org.add_member(user)
      assert other_org.direct_or_team_member?(user)
      refute other_org.adminable_by?(user)

      assert_equal [org], user.owned_or_billing_manager_organizations
    end

    test "includes organizations that the user is a billing manager for" do
      user = create(:user)

      org = create(:organization)
      org.billing.add_manager(user, actor: org.admins.first)

      other_org = create(:organization)
      other_org.add_member(user)

      assert other_org.direct_or_team_member?(user)
      assert org.billing_manager?(user)

      assert_equal [org], user.owned_or_billing_manager_organizations
    end

    test "doesn't include the same org twice" do
      user = create(:user)

      org = create(:organization)
      org.add_member user, action: :admin
      org.billing.add_manager(user, actor: org.admins.first)

      assert org.adminable_by?(user)
      assert org.billing_manager?(user)

      assert_equal [org], user.owned_or_billing_manager_organizations
    end

    test "doesn't include soft-deleted orgs", skip_enterprise: true do
      user = create(:user)

      org = create(:organization)
      org.billing.add_manager(user, actor: org.admins.first)

      other_org = create(:organization)
      other_org.add_member(user)

      assert other_org.direct_or_team_member?(user)
      assert org.billing_manager?(user)

      org.soft_delete!

      assert_empty user.owned_or_billing_manager_organizations
    end
  end

  context "#owned_or_billing_manager_organization_ids" do
    test "includes ID of org the user admins" do
      @org.add_admin(@user)
      assert_includes @user.owned_or_billing_manager_organization_ids, @org.id
    end

    test "includes ID of org the user is billing manager of" do
      @org.billing.add_manager(@user, actor: @org.admin)
      assert_includes @user.owned_or_billing_manager_organization_ids, @org.id
    end

    test "does not include ID of org user is a regular member of" do
      @org.add_member(@user)
      refute_includes @user.owned_or_billing_manager_organization_ids, @org.id
    end

    test "does not include ID of org user has no connection to" do
      refute_includes @user.owned_or_billing_manager_organization_ids, @org.id
    end
  end

  context "#async_verified_company_organizations" do
    test "returns empty array if the user has no profile company" do
      assert_empty @user.async_verified_company_organizations.sync
    end

    test "returns empty array if the user has a company in their profile but is not a member" do
      @user.profile_company = "@#{@org}"
      @user.save!

      assert_empty @user.async_verified_company_organizations.sync
    end

    test "returns empty array if the company is in the profile but not a public membership" do
      @org.add_member(@user)

      @user.profile_company = "@#{@org}"
      @user.save!

      assert_empty @user.async_verified_company_organizations.sync
    end

    test "returns companies that are mentioned in the profile and are real public memberships" do
      @org.add_member(@user)
      @org.publicize_member(@user)

      other_org = create(:organization)
      other_org.add_member(@user)
      other_org.publicize_member(@user)

      @user.profile_company = "works at @#{@org} and @#{other_org}"
      @user.save!

      assert_same_elements [@org, other_org], @user.async_verified_company_organizations.sync
    end
  end

  context "#organization_ids_visible_to" do
    test "returns the org ID if the membership is private but the viewer is also a member" do
      @org.add_member(@user)
      @org.add_member(@viewer)

      assert_same_elements [@org.id], @user.organization_ids_visible_to(@viewer)
    end

    test "returns the org ID if the membership is private but the viewer is self" do
      @org.add_member(@user)

      assert_same_elements [@org.id], @user.organization_ids_visible_to(@user)
    end

    test "returns nothing if the membership is private and the viewer is not a member" do
      @org.add_member(@user)

      assert_empty @user.organization_ids_visible_to(@viewer)
    end

    # https://github.com/github/sponsors/issues/1911
    test "returns nothing if the user does not belong to the org, even when viewer does" do
      @org.add_member(@viewer)

      assert_empty @user.organization_ids_visible_to(@viewer)
    end

    test "returns public organization IDs if the viewer is not in org or nil" do
      @org.add_member(@user)
      @org.publicize_member(@user)

      assert_same_elements [@org.id], @user.organization_ids_visible_to(@viewer)
      assert_same_elements [@org.id], @user.organization_ids_visible_to(nil)
    end

    context "private profiles" do
      test "doesn't return org ids for private profiles if viewer is not an org member" do
        @org.add_member(@user)
        @org.publicize_member(@user)
        @user.update!(private_profile: true)

        assert_empty @user.organization_ids_visible_to(@viewer)
      end

      test "returns org ids for private profiles to viewers with shared org membership" do
        @org.add_member(@user)
        @user.update!(private_profile: true)
        @org.add_member(@viewer)

        assert_same_elements [@org.id], @user.organization_ids_visible_to(@viewer)
      end
    end
  end

  context "#organizations_visible_to" do
    test "returns the org if the membership is private but the viewer is also a member" do
      @org.add_member(@user)
      @org.add_member(@viewer)

      assert_same_elements [@org], @user.organizations_visible_to(@viewer)
    end

    test "returns the org if the membership is private but the viewer is self" do
      @org.add_member(@user)

      assert_same_elements [@org], @user.organizations_visible_to(@user)
    end

    test "returns nothing if the membership is private and the viewer is not a member" do
      @org.add_member(@user)

      assert_empty @user.organizations_visible_to(@viewer)
    end

    test "returns public organizations if the viewer is not in org or nil" do
      @org.add_member(@user)
      @org.publicize_member(@user)

      assert_same_elements [@org], @user.organizations_visible_to(@viewer)
      assert_same_elements [@org], @user.organizations_visible_to(nil)
    end

    test "does not return soft-deleted organizations", skip_enterprise: true do
      @org.add_member(@user)
      @org.add_member(@viewer)
      @org.soft_delete!

      assert_empty @user.organizations_visible_to(@viewer)
      assert_empty @user.organizations_visible_to(@user)
    end
  end

  context "organization_hash" do
    test "contains the correct custom_disabled_message when org is archived" do
      @org.set_archived(@user)

      [:read, :write, :admin].each do |access|
        assert_equal "(Archived)", @user.organization_hash(@org, access)[:custom_disabled_message]
      end
    end

    test "contains no custom_disabled_message when org is not archived" do
      [:read, :write, :admin].each do |access|
        assert_nil @user.organization_hash(@org, access)[:custom_disabled_message]
      end
    end
  end

  context "#async_visible_teams_for" do
    test "doesn't return teams owned by orgs the user isn't a member of" do
      user, viewer = create_pair(:user)
      create(:public_team).add_member(user)

      user.async_visible_teams_for(viewer).then do |teams|
        assert_equal [], teams
      end.sync
    end

    # enterprise mode does not support soft deleted orgs
    test "doesn't return teams owned by soft-deleted orgs", skip_enterprise: true do
      user = create(:user)
      user.enable_feature(:async_visible_teams_for_soft_deleted_org_fix)
      org = create(:organization)
      team = create(:public_team, organization: org)
      team.add_member(user)
      org.soft_delete!

      user.async_visible_teams_for(user).then do |teams|
        assert_equal [], teams
      end.sync
    end

    test "doesn't return teams visible to the viewer that the user isn't a member of" do
      user, viewer = create_pair(:user)
      org = create(:organization)
      user_team = create(:public_team, organization: org)
      user_team.add_member(user)
      viewer_team = create(:public_team, organization: org)
      viewer_team.add_member(viewer)

      teams = user.async_visible_teams_for(viewer).then do |teams|
        assert_equal [user_team], teams
      end.sync
    end

    test "doesn't return teams that are only owned by soft-deleted organizations", skip_enterprise: true do
      user, viewer = create_pair(:user)
      org = create(:organization, admin: viewer)
      user_team = create(:public_team, organization: org)
      user_team.add_member(user)

      org.soft_delete!

      teams = user.async_visible_teams_for(viewer).then do |teams|
        assert_equal [], teams
      end.sync
    end

    test "returns teams in orgs that are owned by the viewer" do
      user, viewer = create_pair(:user)
      org = create(:organization, admin: viewer)
      owned_team = create(:secret_team, organization: org)
      owned_team.add_member(user)

      user.async_visible_teams_for(viewer).then do |teams|
        assert_equal [owned_team], teams, "owner can see all org teams"
      end.sync
    end

    test "returns secret teams that the user and viewers are both members of" do
      user, viewer = create_pair(:user)
      secret_team = create(:secret_team)
      secret_team.add_member(user)
      secret_team.add_member(viewer)

      user.async_visible_teams_for(viewer).then do |teams|
        assert_equal [secret_team], teams
      end.sync
    end

    test "works when viewer can see users teams across multiple orgs" do
      user, viewer = create_pair(:user)
      teams_across_orgs = create_pair(:team)
      teams_across_orgs.each do |team|
        team.add_member(user)
        team.add_member(viewer)
      end

      user.async_visible_teams_for(viewer).then do |teams|
        assert_same_elements teams_across_orgs, teams
      end.sync
    end

    test "returns no teams for an anonymous viewer" do
      user = create(:user)
      viewer = nil
      create(:team).add_member(user)

      user.async_visible_teams_for(viewer).then do |teams|
        assert_equal [], teams
      end.sync
    end

    test "avoids unnecessary queries when viewing your own teams" do
      user = create(:user)
      viewer = user
      teams = create_pair(:team)
      teams.each { |team| team.add_member(user) }

      assert_max_query_count(2) do
        user.async_visible_teams_for(viewer).sync
      end
    end
  end

  context "#solitarily_owned_organizations" do
    test "only returns orgs where the user is the only owner" do
      one = create :organization, admin: @user
      two = create :organization, admin: @user
      two.add_admin(@viewer)
      three = create :organization, admin: @user
      four = create :organization, admin: @user
      four.add_admin(@viewer)
      four.add_admin(create(:user))
      five = create :organization, admin: @user
      five.add_admin(@viewer)
      six = create :organization
      six.add_member(@user)
      seven = create :organization
      seven.add_member(@user)

      assert_runs_sql_queries(total: 4) do
        assert_same_elements [one, three], @user.solitarily_owned_organizations
      end
    end

    test "does not return soft-deleted organizations where the user is the only owner", skip_enterprise: true do
      one = create :organization, admin: @user
      two = create :organization, admin: @user
      two.add_admin(@viewer)
      three = create :organization, admin: @user
      four = create :organization, admin: @user
      four.add_admin(@viewer)
      four.add_admin(create(:user))
      five = create :organization, admin: @user
      five.add_admin(@viewer)
      six = create :organization
      six.add_member(@user)
      seven = create :organization
      seven.add_member(@user)

      one.soft_delete!
      assert_same_elements [three], @user.solitarily_owned_organizations
    end
  end

  context "#authorizable_organizations" do
    test "returns org that user is a direct member of" do
      @org.add_member(@user)

      assert @user.authorizable_organizations.include?(@org)
    end

    test "returns org that own repo that user is an outside collaborator of" do
      repo = create(:repository, owner: @org)
      RepositoryInvitation.invite_to_repo_without_confirmation(@user, @org.owner, repo)

      assert @user.authorizable_organizations.include?(@org)
    end
  end

  context "#resources_for_cap_filter" do
    test "returns orgs that user is directly related to" do
      GitHub.flipper.disable(:cap_filter_consider_outside_collabs)
      @org.add_member(@user)
      billing_org = create(:enterprise_linked_organization)
      billing_org.business.add_owner(@user, actor: nil)
      collab_org = create(:organization)
      repo = create(:repository, owner: collab_org)
      RepositoryInvitation.invite_to_repo_without_confirmation(@user, collab_org.owner, repo)

      assert @user.resources_for_cap_filter.include?(@org)
      refute @user.resources_for_cap_filter.include?(billing_org)
      refute @user.resources_for_cap_filter.include?(collab_org)
    end

    test "with param, returns orgs that user is directly and indirectly related to" do
      GitHub.flipper.disable(:cap_filter_consider_outside_collabs)
      @org.add_member(@user)
      billing_org = create(:enterprise_linked_organization)
      billing_org.business.add_owner(@user, actor: nil)
      collab_org = create(:organization)
      repo = create(:repository, owner: collab_org)
      RepositoryInvitation.invite_to_repo_without_confirmation(@user, collab_org.owner, repo)

      assert @user.resources_for_cap_filter(direct_and_indirect_orgs: true).include?(@org)
      assert @user.resources_for_cap_filter(direct_and_indirect_orgs: true).include?(billing_org)
      refute @user.resources_for_cap_filter(direct_and_indirect_orgs: true).include?(collab_org)
    end

    test "with cap_filter_consider_outside_collabs FF, also returns orgs that own repos user is an outside collaborator of" do
      GitHub.flipper.enable(:cap_filter_consider_outside_collabs)
      @org.add_member(@user)
      billing_org = create(:enterprise_linked_organization)
      billing_org.business.add_owner(@user, actor: nil)
      collab_org = create(:organization)
      repo = create(:repository, owner: collab_org)
      RepositoryInvitation.invite_to_repo_without_confirmation(@user, collab_org.owner, repo)

      assert @user.resources_for_cap_filter.include?(@org)
      refute @user.resources_for_cap_filter.include?(billing_org)
      assert @user.resources_for_cap_filter.include?(collab_org)
    end
  end
end

module UserOrganizationsDependencySharedTests
  include AuthenticationHelpers::SAML
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { UserOrganizationsDependencyBaseTest }

  included do
    T.bind(self, T.class_of(UserOrganizationsDependencyBaseTest))

    context "#filter_organizations" do
      test "returns all user organizations if the viewer is an owner of an enterprise" do
        assert_same_elements display_login(@org1, @org2, @org4), @member1.filter_organizations(@owner).pluck(:display_login)
      end

      test "returns some user organizations if the viewer is an admin of an organization" do
        assert_same_elements display_login(@org1), @member1.filter_organizations(@admin1).pluck(:display_login)
        assert_same_elements display_login(@org2, @org3), @member2.filter_organizations(@admin2).pluck(:display_login)
      end

      test "returns all user organizations if the viewer is self" do
        assert_same_elements display_login(@org1, @org2, @org4), @member1.filter_organizations(@member1).pluck(:display_login)
      end

      test "returns second user organizations if the filter query was specified" do
        assert_same_elements display_login(@org2), @member1.filter_organizations(@owner, query: "second").pluck(:display_login)
      end

      test "returns nothing if the user organizations if the filter query does not select an organization" do
        assert_empty @member1.filter_organizations(@owner, query: "third")
      end

      test "returns user organizations where user is an admin if the filter member type was specified" do
        org_role = ::BusinessUserAccount.org_member_type_from_role(::Platform::Enums::EnterpriseUserAccountMembershipRole.values["OWNER"]&.value)
        assert_same_elements display_login(@org4), @member1.filter_organizations(@owner, org_member_type: org_role).pluck(:display_login)
      end

      test "returns user organizations where user is a member if the filter member type was specified" do
        org_role = ::BusinessUserAccount.org_member_type_from_role(::Platform::Enums::EnterpriseUserAccountMembershipRole.values["MEMBER"]&.value)
        assert_same_elements display_login(@org1, @org2), @member1.filter_organizations(@owner, org_member_type: org_role).pluck(:display_login)
      end

      test "does not return soft-deleted organizations", skip_enterprise: true do
        @org1.soft_delete!

        assert_same_elements display_login(@org2, @org4), @member1.filter_organizations(@owner).pluck(:display_login)
        assert_empty @member1.filter_organizations(@admin1).pluck(:display_login)
        assert_same_elements display_login(@org2, @org4), @member1.filter_organizations(@member1).pluck(:display_login)
        org_role = ::BusinessUserAccount.org_member_type_from_role(::Platform::Enums::EnterpriseUserAccountMembershipRole.values["MEMBER"]&.value)
        assert_same_elements display_login(@org2), @member1.filter_organizations(@owner, org_member_type: org_role).pluck(:display_login)
      end
    end

    context "#organization_ids_visible_to" do
      test "enterprise admin cannot see organizations for a user unless has access" do
        assert_empty @member1.organization_ids_visible_to(@owner)
      end

      test "returns some user organization ids if the viewer is an admin of an organization" do
        assert_same_elements [@org1.id], @member1.organization_ids_visible_to(@admin1)
        assert_same_elements [@org2, @org3].map(&:id), @member2.organization_ids_visible_to(@admin2)
      end

      test "does not return soft-deleted organizations", skip_enterprise: true do
        @org1.soft_delete!
        @org2.soft_delete!
        assert_empty @member1.organization_ids_visible_to(@admin1)
        assert_same_elements [@org3].map(&:id), @member2.organization_ids_visible_to(@admin2)
      end
    end

    context "#filter_teams" do
      test "returns all user teams if the viewer is an owner of an enterprise" do
        assert_same_elements id_array(@team1, @team2), @member1.filter_teams(@owner).pluck(:id)
      end

      test "returns some user teams if the viewer is an admin of an organization" do
        assert_same_elements id_array(@team1), @member1.filter_teams(@admin1).pluck(:id)
        assert_same_elements id_array(@team2, @team3), @member2.filter_teams(@admin2).pluck(:id)
      end

      test "returns all user teams if the viewer is self" do
        assert_same_elements id_array(@team1, @team2), @member1.filter_teams(@member1).pluck(:id)
      end

      test "returns second user teams if the filter query was specified" do
        assert_same_elements id_array(@team1), @member1.filter_teams(@owner, query: "first").pluck(:id)
      end

      test "returns nothing if the user teams if the filter query does not select a team" do
        assert_empty @member1.filter_teams(@owner, query: "third")
      end

      test "does not return teams from a soft-deleted organization", skip_enterprise: true do
        @org1.soft_delete!

        assert_same_elements id_array(@team2), @member1.filter_teams(@owner).pluck(:id)
      end

      test "does not return teams from a deleted organization" do
        @org1.update!(deleted: 1)

        assert_same_elements id_array(@team2), @member1.filter_teams(@owner).pluck(:id)
      end
    end
  end
end

class UserOrganizationsDependencyBaseTest < GitHub::TestCase
  def display_login(*orgs)
    orgs.map(&:display_login)
  end

  def id_array(*teams)
    teams.map(&:id)
  end
end

class GHESUserOrganizationsDependencyTest < UserOrganizationsDependencyBaseTest
  skip_unless :enterprise?

  include UserOrganizationsDependencySharedTests

  fixtures do
    @business = create(:global_business)
    @member1 = create :user, login: "member1"
    @member2 = create :user, login: "member2"
    @owner = create :user, login: "owner"
    @business.add_owner(@owner, actor: nil)

    @admin1 = create :user, login: "orgadmin1"
    @admin2 = create :user, login: "orgadmin2"

    @org1 = create :organization, admins: [@admin1], name: "First-org"
    @org2 = create :organization, admins: [@admin2], name: "Second-org"
    @org3 = create :organization, admins: [@admin2], name: "Third-org"
    @org4 = create :organization, admins: [@member1], name: "Fourth-org"

    @org1.add_member(@member1)
    @org2.add_member(@member1)
    @org2.add_member(@member2)
    @org3.add_member(@member2)

    @team1 = create :team, organization: @org1, name: "First-team"
    @team2 = create :team, organization: @org2, name: "Second-team"
    @team3 = create :team, organization: @org3, name: "Third-team"

    @team1.add_member(@member1)
    @team2.add_member(@member1)
    @team2.add_member(@member2)
    @team3.add_member(@member2)
  end
end

class GHESWithSCIMUserOrganizationsDependencyTest < UserOrganizationsDependencyBaseTest
  skip_unless :enterprise?

  include UserOrganizationsDependencySharedTests

  fixtures do
    setup_saml_auth_mode(with_scim: true)
    @business = create(:global_business)
    @member1 = create :user, login: "member1" # a non-scim provisioned user
    @member2 = create :ghes_scim_user, login: "member2"
    @owner = create :ghes_scim_user, :admin, login: "owner"
    @admin1 = create :ghes_scim_user, login: "orgadmin1"
    @admin2 = create :ghes_scim_user, login: "orgadmin2"

    @org1 = create :organization, admins: [@admin1], name: "First-org"
    @org2 = create :organization, admins: [@admin2], name: "Second-org"
    @org3 = create :organization, admins: [@admin2], name: "Third-org"
    @org4 = create :organization, admins: [@member1], name: "Fourth-org"

    @org1.add_member(@member1)
    @org2.add_member(@member1)
    @org2.add_member(@member2)
    @org3.add_member(@member2)

    @team1 = create :team, organization: @org1, name: "First-team"
    @team2 = create :team, organization: @org2, name: "Second-team"
    @team3 = create :team, organization: @org3, name: "Third-team"

    @team1.add_member(@member1)
    @team2.add_member(@member1)
    @team2.add_member(@member2)
    @team3.add_member(@member2)
  end

  setup do
    setup_saml_auth_mode(with_scim: true)
  end
end

class EMUUserOrganizationsDependencyTest < UserOrganizationsDependencyBaseTest
  skip_enterprise

  include UserOrganizationsDependencySharedTests

  fixtures do
    @owner = create :emu, :owner, login: "owner", provider_type: :oidc
    @business = @owner.enterprise_managed_business
    @member1 = create :emu, business: @business, login: "member1"
    @member2 = create :emu, business: @business, login: "member2"
    @admin1 = create :emu, business: @business, login: "orgadmin1"
    @admin2 = create :emu, business: @business, login: "orgadmin2"

    @org1 = create :organization, business: @business, admins: [@admin1], name: "First-org"
    @org2 = create :organization, business: @business, admins: [@admin2], name: "Second-org"
    @org3 = create :organization, business: @business, admins: [@admin2], name: "Third-org"
    @org4 = create :organization, business: @business, admins: [@member1], name: "Fourth-org"

    @org1.add_member(@member1)
    @org2.add_member(@member1)
    @org2.add_member(@member2)
    @org3.add_member(@member2)

    @team1 = create :team, organization: @org1, name: "First-team"
    @team2 = create :team, organization: @org2, name: "Second-team"
    @team3 = create :team, organization: @org3, name: "Third-team"

    @team1.add_member(@member1)
    @team2.add_member(@member1)
    @team2.add_member(@member2)
    @team3.add_member(@member2)
  end

  context "#resources_for_cap_filter" do
    test "returns organizations if user level IP enforcement is not enabled" do
      @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::GITHUB)
      create :ip_allowlist_entry, owner: @business, active: true, allow_list_value: "10.10.10.0/24"
      @business.enable_ip_allowlist(actor: @business.owners.first)

      assert_same_elements [@org1, @org2, @org4], @member1.resources_for_cap_filter
    end

    test "returns organizations and users if user level IP enforcement is enabled" do
      GitHub.flipper[:ip_allowlist_user_level_enforcement].enable(@business)
      @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::GITHUB)
      create :ip_allowlist_entry, owner: @business, active: true, allow_list_value: "10.10.10.0/24"
      @business.enable_ip_allowlist(actor: @business.owners.first)
      @business.enable_ip_allowlist_user_level_enforcement(actor: @business.owners.first)

      assert_same_elements [@org1, @org2, @org4, @owner, @member1, @member2, @admin1, @admin2, @business.find_first_emu_owner], @member1.resources_for_cap_filter
    end

    test "returns organizations if CAP enforcement is not enabled" do
      assert_same_elements [@org1, @org2, @org4], @member1.resources_for_cap_filter
    end

    test "returns organizations and users if external CAP enforcement is enabled" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)
      GitHub.flipper[:idp_cap_web_configurable_allowed].enable(@business)
      @business.update_ip_allowlist_configuration(actor: @owner, config_value: Configurable::IpAllowlistConfiguration::IDP)
      @business.enable_idp_ip_allowlist_for_web(actor: @owner)

      assert_same_elements [@org1, @org2, @org4, @owner, @member1, @member2, @admin1, @admin2, @business.find_first_emu_owner], @member1.resources_for_cap_filter
    end
  end
end
