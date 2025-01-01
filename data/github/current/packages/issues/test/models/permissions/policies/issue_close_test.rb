# typed: true
# frozen_string_literal: true

require "test_helper"

class Permissions::IssueCloseTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @user = create(:user, login: "orgMember")
    @repo = create :repository, owner: @user
    @issue = create(:issue,
      repository: @repo,
      user: @user,
      title: "test",
    )
  end

  context "ALLOW" do
    test "user is owner of repo" do
      user = create :user
      issue = create(:issue,
        repository: @repo,
        user: user,
        title: "test",
      )
      decision = ::Permissions::Enforcer.authorize(
        action: :close_issue,
        actor: @user,
        subject: issue,
      )
      assert_equal :ALLOW, decision.result
    end

    test "user is author of issue and has read permission on private repo" do
      any_member = create :user
      repo = create(:private_repository, owner: @user)
      # apparently you can only give write access on user owned repos
      repo.add_member(any_member, action: :write)

      an_issue = create(:issue,
        repository: repo,
        user: any_member,
        title: "test2",
      )

      decision = ::Permissions::Enforcer.authorize(
        action: :close_issue,
        actor: any_member,
        subject: an_issue,
      )
      assert_equal :ALLOW, decision.result
    end

    test "user is author of issue and has implicit read on public repo" do
      any_member = create :user
      repo = create :repository, owner: @user # public by default

      an_issue = create(:issue,
        repository: repo,
        user: any_member,
        title: "test2",
      )

      decision = ::Permissions::Enforcer.authorize(
        action: :close_issue,
        actor: any_member,
        subject: an_issue,
      )
      assert_equal :ALLOW, decision.result
    end

    test "user has write permission on repo" do
      user_with_write = create :user
      @repo.add_member(user_with_write, action: :write)

      decision = ::Permissions::Enforcer.authorize(
        action: :close_issue,
        actor: user_with_write,
        subject: @issue,
      )
      assert_equal :ALLOW, decision.result
    end

    test "user has close-issue FGP" do
      org = create(:business_plus_org)

      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo, user: org.admins.first, title: "test")

      user = create(:user)
      grant_custom_role(user: user, target: repo, base_role: :read, fgps: [:close_issue])

      decision = ::Permissions::Enforcer.authorize(
        action: :close_issue,
        actor: user,
        subject: issue,
      )
      assert_equal :ALLOW, decision.result
    end
  end
end
