# typed: true
# frozen_string_literal: true

require "test_helper"

class UserOrganizationFilterTest < GitHub::TestCase
  fixtures do
    make_trusted_oauth_apps_owner
    @github = make_trusted_oauth_apps_owner
    @user = create(:user)

    @org1 = create(:organization)
    @team1 = create :team, organization: @org1
    @team1.add_member @user

    @org2 = create(:organization)
    @team2 = create :team, organization: @org2
    @team2.add_member @user

    @org3 = create(:organization)
    @team3 = create :team, organization: @org3
    @team4 = create :team, organization: @org3
    @team3.add_member @user
    @team4.add_member @user
  end

  setup do
    @filter = User::OrganizationFilter.new @user
  end

  context "scope" do
    test "returns a list of organizations of which the user is a member" do
      orgs = @filter.scope
      assert_same_elements [@org1, @org2, @org3], orgs
    end

    test "does not return soft-deleted organizations in list of which the user is a member" do
      GitHub.flipper[:soft_delete_organization].enable

      soft_deleted_org = create :organization
      team5 = create :team, organization: soft_deleted_org
      team5.add_member @user
      soft_deleted_org.soft_delete!
      refute_includes @filter.scope, soft_deleted_org
    end
  end

  context "with pagination" do
    test "returns a paginated list" do
      orgs = @filter.scope.paginate page: 1, per_page: 1
      assert_equal [@org1], orgs
      assert_equal 3, orgs.total_pages
      assert_equal 1, orgs.current_page
    end

    test "handles page count when last page is incomplete" do
      orgs = @filter.scope.paginate page: 1, per_page: 2
      assert_same_elements [@org1, @org2], orgs
      assert_equal 2, orgs.total_pages
      assert_equal 1, orgs.current_page
    end

    test "handles the first page when less than a page is present" do
      orgs = @filter.scope.paginate page: 1, per_page: 10
      assert_same_elements [@org1, @org2, @org3], orgs
      assert_equal 1, orgs.total_pages
      assert_equal 1, orgs.current_page
    end
  end

  context "OAuth context" do
    # See #37578
    test "handles filtering by Org Application Policy for GitHub-owned apps" do
      user = create(:user)
      org = create(:organization)
      team = create(:team, organization: org)
      team.add_member user

      app = create :oauth_application, user: GitHub.trusted_oauth_apps_owner
      access = create :oauth_access, application: app, user: user

      user.oauth_access = access
      user.scopes = ["repo"]

      assert_includes user.organizations, org
    end
  end if GitHub.oauth_application_policies_enabled?

  context "#unscoped_ids" do
    test "does not filter by Org Application Policy for GitHub-owned apps" do
      user = create(:user)
      org_with_restrictions_enabled = create(:organization)
      org = create(:organization)
      org_with_restrictions_enabled.enable_oauth_application_restrictions
      org_team = create(:team, organization: org)
      org_with_restrictions_enabled_team = create :team, organization: org_with_restrictions_enabled
      org_team.add_member(user)
      org_with_restrictions_enabled_team.add_member(user)

      app = create(:oauth_application, user: GitHub.trusted_oauth_apps_owner)
      access = create(:oauth_access, application: app, user: user)
      user.oauth_access = access
      user.scopes = ["repo"]

      unscoped_organizations = User::OrganizationFilter.new(user).unscoped_ids

      assert_same_elements [org, org_with_restrictions_enabled].map(&:id), unscoped_organizations
    end

    test "does not include soft-deleted organizations" do
      GitHub.flipper[:soft_delete_organization].enable

      user = create(:user)
      org_with_restrictions_enabled = create(:organization)
      org = create(:organization, login: "soft-deleted-org")
      org_with_restrictions_enabled.enable_oauth_application_restrictions
      org_team = create(:team, organization: org)
      org_with_restrictions_enabled_team = create :team, organization: org_with_restrictions_enabled
      org_team.add_member(user)
      org_with_restrictions_enabled_team.add_member(user)

      app = create(:oauth_application, user: GitHub.trusted_oauth_apps_owner)
      access = create(:oauth_access, application: app, user: user)
      user.oauth_access = access
      user.scopes = ["repo"]

      org.soft_delete!

      unscoped_organizations = User::OrganizationFilter.new(user).unscoped_ids

      assert_same_elements [org_with_restrictions_enabled].map(&:id), unscoped_organizations
    end
  end
end
