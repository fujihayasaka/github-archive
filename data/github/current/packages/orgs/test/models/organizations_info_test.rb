# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationsInfoTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
  end

  test "no organization info returned if user is a billing manager, but not a member of the org" do
    billing_org = create(:organization, login: "billing-mgr-org")
    billing_org.billing.add_manager(@user, actor: billing_org.admins.first)

    orgs_info = @user.organizations_info
    assert_nil orgs_info[billing_org]
  end

  test "no organization info returned if the org has been soft-deleted", skip_enterprise: true do
    soft_deleted_org = create(:organization, admin: @user, login: "soft-deleted-org")
    soft_deleted_org.disallow_members_can_create_repositories(actor: @user)
    soft_deleted_org.soft_delete!
    orgs_info = @user.organizations_info
    assert_nil orgs_info[soft_deleted_org]
  end

  test "returns :admin action if user is an org admin" do
    adminable_org = create(:organization, admin: @user, login: "adminable-corp")
    adminable_org.disallow_members_can_create_repositories(actor: @user)

    orgs_info = @user.organizations_info
    want = { access: :admin, allow_public_repos: true, allow_private_repos: true, allow_internal_repos: adminable_org.supports_internal_repositories? }
    assert_equal want, orgs_info[adminable_org]
  end

  test "returns granular permissions for member with write permissions if only some repo types are disallowed" do
    writable_org = create(:organization, login: "writable-org")
    writable_org.add_member(@user, action: :write)
    writable_org.allow_members_can_create_repositories_with_visibilities(actor: @user,
      public_visibility: !GitHub.enterprise?, private_visibility: true)

    orgs_info = @user.organizations_info
    # public repos can't be disabled for non-enterprise (and non business_plus) orgs
    want = { access: :write, allow_public_repos: !GitHub.enterprise?, allow_private_repos: true, allow_internal_repos: false }
    assert_equal want, orgs_info[writable_org]
  end

  test "returns :write action if user has write permissions to the org" do
    writable_org = create(:organization, login: "writable-org")
    writable_org.add_member(@user, action: :write)
    writable_org.disallow_members_can_create_repositories(actor: @user)

    orgs_info = @user.organizations_info
    want = { access: :write, allow_public_repos: false, allow_private_repos: false, allow_internal_repos: false }
    assert_equal want, orgs_info[writable_org]
  end

  test "returns :read action if user has read permissions to the org" do
    readable_org = create(:organization, login: "readable-org")
    readable_org.add_member(@user, action: :read)
    readable_org.disallow_members_can_create_repositories(actor: @user)

    orgs_info = @user.organizations_info
    want = { access: :read, allow_public_repos: false, allow_private_repos: false, allow_internal_repos: false }
    assert_equal want, orgs_info[readable_org]
  end

  test "returns :write action if user has :read permissions to the org, but the org allows all members to create repos" do
    readable_org_with_create = create(:organization, login: "readable-org-with-create-permissions")
    readable_org_with_create.add_member(@user, action: :read)
    assert(readable_org_with_create.members_can_create_repositories?)

    orgs_info = @user.organizations_info
    want = { access: :write, allow_public_repos: true, allow_private_repos: true,
      allow_internal_repos: readable_org_with_create.supports_internal_repositories? }
    assert_equal want, orgs_info[readable_org_with_create]
  end

  test "returns :admin action if user has :read permission to the org, but is a member of a legacy-admin team" do
    legacy_admins_org = create(:organization, login: "readable-org-with-legacy-admins")
    legacy_admins_org.disallow_members_can_create_repositories(actor: @user)
    legacy_admin_team = create(:team, organization: legacy_admins_org, permission: "admin")
    legacy_admins_org.add_member(@user, action: :read)
    legacy_admin_team.add_member(@user)

    orgs_info = @user.organizations_info
    want = { access: :admin, allow_public_repos: true, allow_private_repos: true,
      allow_internal_repos: legacy_admins_org.supports_internal_repositories? }
    assert_equal want, orgs_info[legacy_admins_org]
  end

  test "returns :read action if user has :read permission to the org, org has a legacy admin team, but user is only a member of its child team" do
    leagacy_admins_org2 = create(:organization, login: "readable-org-with-nested-legacy-admins")
    leagacy_admins_org2.disallow_members_can_create_repositories(actor: @user)
    legacy_admin_team2 = create(:public_team, organization: leagacy_admins_org2, permission: "admin")
    nested_legacy_admin_team = create(:public_team, organization: leagacy_admins_org2, parent_team_id: legacy_admin_team2.id)
    leagacy_admins_org2.add_member(@user, action: :read)
    nested_legacy_admin_team.add_member(@user)

    orgs_info = @user.organizations_info
    want = { access: :read, allow_public_repos: false, allow_private_repos: false, allow_internal_repos: false }
    assert_equal want, orgs_info[leagacy_admins_org2]
  end

  test "runs only one query per table for a user member of many orgs (can create repos)" do
    create_list(:organization, 5).each do |org|
      org.add_member(@user)
    end

    assert_query_count_per_table({ configuration_entries: 1, profiles: 1, trade_controls_restrictions: 1, teams: 0 }) do
      @user.organizations_info
    end
  end

  test "runs only one query per table for a user member of many orgs (cannot create repos)" do
    orgs = create_list(:organization, 5).each do |org|
      org.disallow_members_can_create_repositories(actor: @user)

      team = create :team, organization: org
      team.add_member(@user)
    end

    assert_query_count_per_table({ configuration_entries: 1, profiles: 1, trade_controls_restrictions: 1, teams: 1 }) do
      @user.organizations_info
    end
  end

  test "returns the expected amount of queries per table for a user admin of many orgs" do
    create_list(:organization, 5, admin: @user)

    # Won't preload configuration_entries if user is admin of the org
    assert_query_count_per_table({ configuration_entries: 0, profiles: 1, trade_controls_restrictions: 1, teams: 0 }) do
      @user.organizations_info
    end

    if GitHub.enterprise?
      @enterprise_business = create(:business, owners: [@user])
      5.times { @enterprise_business.add_organization(create(:organization, plan: GitHub::Plan.enterprise, admins: [@user])) }
      assert_query_count_per_table({ configuration_entries: 0, businesses: 1, profiles: 1, trade_controls_restrictions: 1, teams: 0 }) do
        @user.organizations_info
      end
    end
  end
end
