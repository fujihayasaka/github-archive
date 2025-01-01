# typed: true
# frozen_string_literal: true

require "test_helper"

class Permissions::SetIssueMilestonesTest < GitHub::TestCase

  fixtures do
    @owner = create(:user)
    @repo = create(:repository, owner: @owner)
    @issue = create(:issue,
      repository: @repo,
      user: @owner,
      title: "test",
    )

    @org = create(:business_plus_organization)
    @org_repo = create(:repository, owner: @org)
    @org_repo_issue = create(:issue, repository: @org_repo)
    @org_team = create(:team, organization: @org)
  end

  context "ALLOW" do
    test "user is owner of repo" do
      decision = ::Permissions::Enforcer.authorize(
        action: :set_milestone,
        actor: @owner,
        subject: @issue,
      )

      assert_equal :ALLOW, decision.result
    end

    test "user has write permission on repo" do
      user_with_write = create(:user)
      @repo.add_member(user_with_write, action: :write)

      decision = ::Permissions::Enforcer.authorize(
        action: :set_milestone,
        actor: user_with_write,
        subject: @issue,
      )

      assert_equal :ALLOW, decision.result
    end

    test "user has admin permission on repo" do
      user_with_admin = create(:user)
      @org_repo.add_member(user_with_admin, action: :admin)

      decision = ::Permissions::Enforcer.authorize(
        action: :set_milestone,
        actor: user_with_admin,
        subject: @org_repo_issue,
      )

      assert_equal :ALLOW, decision.result
    end

    test "user has write through an org team on repo" do
      user_with_write_via_team = create(:user)
      @org_team.add_member(user_with_write_via_team)
      @org_team.add_repository @org_repo, :push

      decision = ::Permissions::Enforcer.authorize(
        action: :set_milestone,
        actor: user_with_write_via_team,
        subject: @org_repo_issue,
      )

      assert_equal :ALLOW, decision.result
    end

    test "user has triage role on organization owned repo" do
      user_with_triage = create(:user)
      @org_repo.add_member(user_with_triage, action: :triage)

      decision = ::Permissions::Enforcer.authorize(
        action: :set_milestone,
        actor: user_with_triage,
        subject: @org_repo_issue,
      )

      assert_equal :ALLOW, decision.result
    end
  end

  context "DENY" do
    test "user has no permission on repo" do
      user = create(:user)

      decision = ::Permissions::Enforcer.authorize(
        action: :set_milestone,
        actor: user,
        subject: @issue,
      )

      assert_equal :DENY, decision.result
    end

    test "user has read permission on repo" do
      user_with_read = create(:user)
      @repo.add_member(user_with_read, action: :read)

      decision = ::Permissions::Enforcer.authorize(
        action: :set_milestone,
        actor: user_with_read,
        subject: @issue,
      )

      assert_equal :DENY, decision.result
    end

    test "user has read through an org team on repo" do
      user_with_read_via_team = create(:user)
      @org_team.add_member(user_with_read_via_team)
      @org_team.add_repository @org_repo, :pull

      decision = ::Permissions::Enforcer.authorize(
        action: :set_milestone,
        actor: user_with_read_via_team,
        subject: @org_repo_issue,
      )

      assert_equal :DENY, decision.result
    end

    test "when repository is archived" do
      @repo.set_archived

      decision = ::Permissions::Enforcer.authorize(
        action: :set_milestone,
        actor: @owner,
        subject: @issue,
      )

      assert_equal :DENY, decision.result
    end
  end
end
