# typed: true
# frozen_string_literal: true
require "test_helper"

class ReleaseAuthTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "owner")
    @author = create(:user, login: "author")
    @repo = create(:repository, owner: @owner, name: "repo", from_example: :simple)
    @release = create(:release, tag_name: "v1", name: "Version One!", author: @owner, repository: @repo, body: "<p>Hello world</p>")
  end

  context "authorization" do
    test "delegates permission attributes to releases" do
      expected_attributes = {
        "subject.type" => "Release",
        "subject.id" => @release.id,
        "subject.repository.id" => @release.repository_id,
        "subject.repository.owner.id" => @release.repository.owner.id,
        "subject.repository.public" => @release.repository.public?,
        "subject.repository.owner.type"  => @release.repository.owner.class.name,
        "subject.owning_organization.id" => @release.repository.owning_organization_id,
        "subject.business.id" => @release.repository.owner&.async_business&.sync&.id,
      }

      assert_equal expected_attributes, @release.permissions_wrapper.subject_attributes
    end

    test "policy allows pusher to receive a release notification on a public repo" do
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: @release.actor,
        subject: @release,
      )

      assert_equal :ALLOW, decision.result
    end
  end

  context "authorization v2" do
    test "policy allows pusher to receive a notification on a public repo" do
      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: @release.actor,
        subject: @release,
        context: {
          version: 2,
          "notification.initiator.id": @release.actor.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :ALLOW, decision.result
    end

    test "policy blocks user that is spammy" do
      user = create(:spammy_user)
      repository = create(:public_repository, owner: user, from_example: :simple)
      release = create(:release, tag_name: "v2", name: "Version Two!", author: user, repository: repository, body: "<p>Hello world</p>")

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: user,
        subject: release,
        context: {
          version: 2,
          "notification.initiator.id": release.actor.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end

    test "policy blocks user that is suspended" do
      user = create(:suspended_user)
      repository = create(:public_repository, owner: user, from_example: :simple)
      release = create(:release, tag_name: "v2", name: "Version Two!", author: user, repository: repository, body: "<p>Hello world</p>")

      decision = ::Permissions::Enforcer.authorize(
        action: :receive_notification,
        actor: user,
        subject: release,
        context: {
          version: 2,
          "notification.initiator.id": release.actor.id,
          "notification.initiator.type": "User",
        },
      )

      assert_equal :DENY, decision.result
    end
  end
end
