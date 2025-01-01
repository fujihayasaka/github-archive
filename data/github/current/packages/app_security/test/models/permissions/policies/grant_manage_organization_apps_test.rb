# typed: true
# frozen_string_literal: true
require "test_helper"

class Permissions::GrantManageOrganizationAppsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @owner = @org.admins.first
    @member = create(:user, login: "orgMember")
    @non_member = create(:user, login: "nonMember")
    @org.add_member(@member)
  end

  context "#authorize" do
    test "denies when actor is not a member of the organization" do
      decision = ::Permissions::Enforcer.authorize(
        action: :grant_manage_organization_apps,
        actor: @non_member,
        subject: @org,
      )

      assert_equal :DENY, decision.result
      assert_equal "grant-manage-github-apps: policy was not met", decision.reason
    end

    test "denies when actor is a member but not an owner of the organization" do
      decision = ::Permissions::Enforcer.authorize(
        action: :grant_manage_organization_apps,
        actor: @member,
        subject: @org,
      )

      assert_equal  :DENY, decision.result
      assert_equal "grant-manage-github-apps: policy was not met", decision.reason
    end

    test "allows when actor is an owner of the organization" do
      decision = ::Permissions::Enforcer.authorize(
        action: :grant_manage_organization_apps,
        actor: @owner,
        subject: @org,
      )

      assert_equal :ALLOW, decision.result
    end
  end
end
