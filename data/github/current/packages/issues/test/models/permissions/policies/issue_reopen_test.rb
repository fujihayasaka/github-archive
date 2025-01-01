# typed: true
# frozen_string_literal: true

require "test_helper"

class Permissions::IssueReopenTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    @user = create(:user, login: "orgMember")
  end

  context "ALLOWED" do
    test "user has read on repo and closed the issue" do
    end

    test "user owns private repo" do
      any_member = create :user
      repo = create(:private_repository, owner: @user)
      repo.add_member(any_member, action: :write)

      issue = create(:issue,
        repository: repo,
        user: any_member,
        title: "test",
      )
      issue.close

      decision = ::Permissions::Enforcer.authorize(
        action: :reopen_issue,
        actor: @user,
        subject: issue,
      )
      assert_equal :ALLOW, decision.result, "unexpected authzd decision #{decision.result}: #{decision.reason}"
    end

    test "user has write on private repo" do
      any_member = create :user
      any_other_member = create :user
      repo = create(:private_repository, owner: @user)
      repo.add_member(any_member, action: :write)
      repo.add_member(any_other_member, action: :write)
      issue = create(:issue,
        repository: repo,
        user: any_member,
        title: "test",
      )
      issue.close

      decision = ::Permissions::Enforcer.authorize(
        action: :reopen_issue,
        actor: any_other_member,
        subject: issue,
      )
      assert_equal :ALLOW, decision.result, "unexpected authzd decision #{decision.result}: #{decision.reason}"
    end

    test "user has reopen_issue FGP" do
      org = create(:business_plus_org)

      repo = create(:repository, owner: org)
      issue = create(:issue, repository: repo, user: org.admins.first, title: "test")
      issue.close

      user = create(:user)
      grant_custom_role(user: user, target: repo, base_role: :read, fgps: [:reopen_issue])

      decision = ::Permissions::Enforcer.authorize(
        action: :reopen_issue,
        actor: user,
        subject: issue,
      )
      assert_equal :ALLOW, decision.result
    end
  end
end
