# typed: true
# frozen_string_literal: true
require "test_helper"

class Permissions::ManageAppTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @app = create(:integration, owner: @org)
    @owner = @org.admins.first
    @member = create(:user, login: "orgMember")
    @org.add_member(@member)
  end

  context "#authorize" do
    test "denies when actor has not been granted apps management permission" do
      decision = ::Permissions::Enforcer.authorize(
        action: :manage_app,
        actor: @member,
        subject: @app,
      )

      assert_equal :DENY, decision.result
      assert_equal "can-manage-single-github-app: policy was not met", decision.reason
    end

    test "allows when actor has been granted management permission on this App" do
      assert_predicate ::Permissions::Granter.grant(
        action: :manage_app,
        actor_id: @member.id,
        subject_id: @app.id,
      ), :success?

      decision = ::Permissions::Enforcer.authorize(
        action: :manage_app,
        actor: @member,
        subject: @app,
      )

      assert_equal :ALLOW, decision.result
    end

    test "allows when actor has been granted apps management permission on the Org" do
      assert_predicate ::Permissions::Granter.grant(
        action: :manage_all_apps,
        actor_id: @member.id,
        subject_id: @org.id,
      ), :success?

      decision = ::Permissions::Enforcer.authorize(
        action: :manage_app,
        actor: @member,
        subject: @app,
      )

      assert_equal :ALLOW, decision.result
    end

    test "allows when actor is an owner of the organization" do
      decision = ::Permissions::Enforcer.authorize(
        action: :manage_app,
        actor: @owner,
        subject: @app,
      )

      assert_equal :ALLOW, decision.result
    end

    test "allows when the actor is the owner of the App" do
      user_app = create(:integration, owner: @owner)

      decision = ::Permissions::Enforcer.authorize(
        action: :manage_app,
        actor: @owner,
        subject: user_app,
      )

      assert_equal :ALLOW, decision.result
    end

    test "denies when the actor is not the owner of the App" do
      rando = create(:user)
      user_app = create(:integration, owner: @owner)

      decision = ::Permissions::Enforcer.authorize(
        action: :manage_app,
        actor: rando,
        subject: user_app,
      )

      assert_equal :DENY, decision.result
      assert_equal "can-manage-single-github-app: policy was not met", decision.reason
    end
  end
end
