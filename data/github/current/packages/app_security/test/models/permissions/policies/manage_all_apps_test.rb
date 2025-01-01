# typed: true
# frozen_string_literal: true
require "test_helper"

class Permissions::ManageAllAppsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @owner = @org.admins.first
    @member = create(:user, login: "orgMember")
    @org.add_member(@member)
  end

  context "#authorize" do
    test "denies when actor has not been granted apps management permission" do
      decision = ::Permissions::Enforcer.authorize(
        action: :manage_all_apps,
        actor: @member,
        subject: @org,
      )

      assert_equal :DENY, decision.result
      assert_equal "can-manage-all-github-apps: policy was not met", decision.reason
    end

    test "allows when actor has been granted apps management permission" do
      assert_predicate ::Permissions::Granter.grant(
        action: :manage_all_apps,
        actor_id: @member.id,
        subject_id: @org.id,
      ), :success?

      decision = ::Permissions::Enforcer.authorize(
        action: :manage_all_apps,
        actor: @member,
        subject: @org,
      )

      assert_equal :ALLOW, decision.result
    end

    test "allows when actor is an owner of the organization" do
      decision = ::Permissions::Enforcer.authorize(
        action: :manage_all_apps,
        actor: @owner,
        subject: @org,
      )

      assert_equal :ALLOW, decision.result
    end
  end
end
