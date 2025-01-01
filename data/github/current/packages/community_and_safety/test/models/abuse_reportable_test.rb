# typed: true
# frozen_string_literal: true

require "test_helper"

class AbuseReportableTest < GitHub::TestCase
  fixtures do
    @commit_comment = create(:commit_comment)
  end

  test "has_many abuse_reports" do
    abuse_report = create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment)

    assert_equal [abuse_report], @commit_comment.abuse_reports
  end

  test "#report_count" do
    abuse_report = create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment)

    assert_equal 1, @commit_comment.report_count
  end

  test "#top_report_reason" do
    create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment, reason: "spam")
    create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment, reason: "spam")
    create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment, reason: "abuse")
    create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment)

    assert_equal "spam", @commit_comment.top_report_reason
  end

  test "#last_reported_at" do
    create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment, reason: "spam")
    create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment, reason: "spam")
    create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment, reason: "abuse")
    last = create(:abuse_report, reporting_user: create(:user), reported_user: create(:user), repository: create(:repository), reported_content: @commit_comment)

    assert_equal last.created_at, @commit_comment.last_reported_at
  end

  test "is AbuseReportable" do
    assert CommitComment.new.is_a? AbuseReportable
    assert Issue.new.is_a? AbuseReportable
    assert IssueComment.new.is_a? AbuseReportable
    assert PullRequest.new.is_a? AbuseReportable
    assert PullRequestReview.new.is_a? AbuseReportable
    assert PullRequestReviewComment.new.is_a? AbuseReportable
    assert Discussion.new.is_a? AbuseReportable
  end

  test "#url" do
    assert CommitComment.new.respond_to?(:url)
    assert Issue.new.respond_to?(:url)
    assert IssueComment.new.respond_to?(:url)
    assert PullRequest.new.respond_to?(:url)
    assert PullRequestReview.new.respond_to?(:url)
    assert PullRequestReviewComment.new.respond_to?(:url)
    assert Discussion.new.respond_to?(:url)
  end
end

class AccessControlForReportingTest < GitHub::TestCase
  fixtures do
    User.create_ghost
    @user = create(:user)
    @owner = create(:user)
    @collaborator = create(:user)
    @repo = create(:repository, owner: @owner, from_example: :pull_request_source)
    @repo.add_member(@collaborator)

    @fork = create(:fork_repository, forker: @user, fork_repo: @repo, from_example: :pull_request_fork)

    @pull = PullRequest.create_for! @repo,
      user: @user,
      title: "test PR",
      body: "body",
      base: "#{@repo.owner.login}:master",
      head: "#{@user.display_login}:master-plus-one-commit"

    @issue = create(:issue, repository:  @repo)
    @user_repo_comment = create(:issue_comment, issue: @issue)

    @org = create(:organization, admin: @owner)
    @org_member = create(:user)
    @org.add_member(@org_member, action: :read)
    @org_repo = create :repository, owner: @org, name: "org-public", from_example: :pages
    @org_repo.enable_tiered_reporting(actor: @owner)
    @org_repo.add_member(@collaborator, action: :read)

    @org_repo_all_users = create :repository, owner: @org, name: "org-all-users"
    @org_repo_all_users.enable_tiered_reporting_all_users(actor: @owner)
    @org_all_users_issue = create(:issue, repository: @org_repo_all_users)
    @org_all_users_comment = create(:issue_comment, issue: @org_all_users_issue)

    @org_issue = create(:issue, repository:  @org_repo)
    @org_comment = create(:issue_comment, issue: @org_issue)
    @admin_comment = create(:issue_comment, issue: @org_issue, user: @owner)

    @prior_contributor = create(:user)

    create(:commit_contribution, :with_summaries, repository: @repo, user: @prior_contributor, committed_date: Time.now.to_date)
    create(:commit_contribution, :with_summaries, repository: @org_repo, user: @prior_contributor, committed_date: Time.now.to_date)
  end

  context "async_viewer_can_report?" do
    if GitHub.can_report?
      test "cannot report private repository" do
        @repo.private = true
        @repo.save!

        refute @user_repo_comment.async_viewer_can_report?(@collaborator).sync
      end

      test "anonymous user cannot report a comment" do
        refute @user_repo_comment.async_viewer_can_report?(nil).sync
      end

      test "unaffiliated user cannot report comment" do
        new_user = create(:user)
        refute @user_repo_comment.async_viewer_can_report?(new_user).sync
      end

      test "prior contributor can report issue in user-owned repo" do
        assert @user_repo_comment.async_viewer_can_report?(@prior_contributor).sync
      end

      test "prior contributor can report issue in org-owned repo" do
        assert @org_issue.async_viewer_can_report?(@prior_contributor).sync
      end

      test "repo member can report comment" do
        assert @user_repo_comment.async_viewer_can_report?(@collaborator).sync
      end

      test "repo member can report issue" do
        assert @issue.async_viewer_can_report?(@collaborator).sync
      end

      test "repo member can report PR" do
        assert @pull.async_viewer_can_report?(@collaborator).sync
      end

      test "org member can report comment" do
        assert @org_comment.async_viewer_can_report?(@org_member).sync
      end

      test "prior contributor blocked by user cannot report comment" do
        assert @user_repo_comment.async_viewer_can_report?(@prior_contributor).sync

        @owner.block(@prior_contributor)

        user_repo_comment = IssueComment.find(@user_repo_comment.id)
        refute user_repo_comment.async_viewer_can_report?(@prior_contributor).sync
      end

      test "prior contributor blocked by org cannot report comment" do
        assert @org_comment.async_viewer_can_report?(@prior_contributor).sync

        @org.block(@prior_contributor)

        org_comment = IssueComment.find(@org_comment.id)
        refute org_comment.async_viewer_can_report?(@prior_contributor).sync
      end

      test "collaborator blocked by user is removed and cannot report comment" do
        assert @repo.writable_by?(@collaborator)

        perform_enqueued_jobs(only: [IgnoreUserJob]) do
          @owner.block(@collaborator)
        end

        refute @repo.writable_by?(@collaborator)
        refute @user_repo_comment.async_viewer_can_report?(@collaborator).sync
      end

      test "collaborator blocked by org is removed and cannot report comment" do
        assert @org_repo.member?(@collaborator)

        perform_enqueued_jobs(only: [IgnoreUserJob]) do
          @org.block(@collaborator)
        end

        refute @org_repo.member?(@collaborator)
        refute @org_comment.async_viewer_can_report?(@collaborator).sync
      end

      test "in a user repo, unaffiliated user can report only their own comment and only if edited by another person" do
        new_user = create(:user)
        new_comment = create(:issue_comment, issue: @issue, user: new_user)
        refute new_comment.async_viewer_can_report?(new_user).sync

        new_comment.update_body(":poop:", @owner)
        new_comment = IssueComment.find(new_comment.id)

        assert new_comment.async_viewer_can_report?(new_user).sync
      end

      test "in an org repo, unaffiliated user can report only their own comment and only if edited by another person" do
        new_user = create(:user)
        new_comment = create(:issue_comment, issue: @org_issue, user: new_user)
        refute new_comment.async_viewer_can_report?(new_user).sync

        new_comment.update_body(":poop:", @owner)
        new_comment = IssueComment.find(new_comment.id)

        assert new_comment.async_viewer_can_report?(new_user).sync
      end

      test "can report PRs authored by a ghost user" do
        @user.delete

        assert @pull.async_viewer_can_report?(@collaborator).sync
      end

      test "can report minimized comments" do
        @user_repo_comment.set_minimized(@owner, "quite rude", "OFF_TOPIC", @user_repo_comment.user)
        assert @user_repo_comment.minimized?

        assert @user_repo_comment.async_viewer_can_report?(@owner).sync
      end

      test "true if tiered reporting for all users is enabled" do
        @org_repo.disable_tiered_reporting(actor: @owner)
        @org_repo.enable_tiered_reporting_all_users(actor: @owner)

        new_user = create(:verified_user)

        assert @org_issue.async_viewer_can_report?(new_user).sync
      end

      test "false if tiered reporting for all users is disabled" do
        @org_repo.disable_tiered_reporting(actor: @owner)
        @org_repo.disable_tiered_reporting_all_users(actor: @owner)

        new_user = create(:verified_user)

        refute @org_issue.async_viewer_can_report?(new_user).sync
      end
    else
      test "repo member cannot report comment" do
        refute @user_repo_comment.async_viewer_can_report?(@owner).sync
      end

      test "org member cannot report issue" do
        refute @org_issue.async_viewer_can_report?(@org_member).sync
      end

      test "repo member cannot report issue" do
        refute @issue.async_viewer_can_report?(@collaborator).sync
      end

      test "repo member cannot report PR" do
        refute @pull.async_viewer_can_report?(@collaborator).sync
      end

      test "repo owner cannot report their own comment even if edited by another person" do
        new_user = create(:user)
        @repo.add_member(new_user)
        @repo.update_member(new_user, action: :admin)
        new_comment = create(:issue_comment, issue: @issue, user: new_user)

        refute new_comment.async_viewer_can_report?(new_user).sync

        new_comment.update_body(":poop:", @owner)

        refute new_comment.async_viewer_can_report?(new_user).sync
      end

      test "repo member cannot report their own comment even if edited by another person" do
        new_user = create(:user)
        @repo.add_member(new_user)
        new_comment = create(:issue_comment, issue: @issue, user: new_user)
        refute new_comment.async_viewer_can_report?(new_user).sync

        new_comment.update_body(":poop:", @owner)

        refute new_comment.async_viewer_can_report?(new_user).sync
      end

      test "cannot report PRs authored by a ghost user" do
        @user.delete

        refute @pull.async_viewer_can_report?(@collaborator).sync
      end

      test "cannot report minimized comments" do
        @user_repo_comment.set_minimized(@owner, "quite rude", "OFF_TOPIC", @user_repo_comment.user)
        assert @user_repo_comment.minimized?

        refute @user_repo_comment.async_viewer_can_report?(@owner).sync
      end
    end
  end

  context "async_viewer_can_report_to_maintainer?" do
    if GitHub.can_report?
      test "false for repo admin" do
        refute @org_comment.async_viewer_can_report_to_maintainer?(@owner).sync
      end

      test "false if comment was made by admin" do
        refute @admin_comment.async_viewer_can_report_to_maintainer?(@org_member).sync
      end

      test "false for a user-owned repository" do
        @repo.enable_tiered_reporting(actor: @owner)

        refute @pull.async_viewer_can_report_to_maintainer?(@collaborator).sync
      end

      test "false when feature is disabled on the repository" do
        @org_repo.disable_tiered_reporting(actor: @owner)

        refute @org_comment.async_viewer_can_report_to_maintainer?(@org_member).sync
      end

      test "false when all users is disabled and user is not a prior contributor" do
        @org_repo.disable_tiered_reporting(actor: @owner)
        @org_repo.disable_tiered_reporting_all_users(actor: @owner)
        new_user = create(:verified_user)

        refute @org_comment.async_viewer_can_report_to_maintainer?(new_user).sync
      end

      test "true when all users is enabled and user is not a prior contributor" do
        @org_repo.disable_tiered_reporting(actor: @owner)
        @org_repo.enable_tiered_reporting_all_users(actor: @owner)
        new_user = create(:verified_user)

        assert @org_comment.async_viewer_can_report_to_maintainer?(new_user).sync
      end

      test "true when user is a collaborator" do
        @org_repo.disable_tiered_reporting(actor: @owner)
        @org_repo.enable_tiered_reporting_all_users(actor: @owner)

        assert @org_comment.async_viewer_can_report_to_maintainer?(@collaborator).sync
      end

      test "true for an org-owned repository for an org member" do
        assert @org_comment.async_viewer_can_report_to_maintainer?(@org_member).sync
      end

      test "true for an org-owned repository for a collaborator" do
        assert @org_comment.async_viewer_can_report_to_maintainer?(@collaborator).sync
      end

      test "true for an org-owned repository for a prior contributor" do
        assert @org_comment.async_viewer_can_report_to_maintainer?(@prior_contributor).sync
      end
    else
      test "false for an org-owned repository for an org member" do
        refute @org_comment.async_viewer_can_report_to_maintainer?(@org_member).sync
      end
    end
  end
end
