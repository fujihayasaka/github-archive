# typed: true
# frozen_string_literal: true

require "test_helper"

class User::InteractionsDependencyTest < GitHub::TestCase
  fixtures do
    @ryan   = create :user, email: "rtomayko@gmail.com", login: "rtomayko"
    @ari    = create :user, login: "ari"
    @bwalsh = create :user, login: "bwalsh"
    @vince  = create :staff_admin_user, login: "vince"

    @source = create :repository, owner: @ari, from_example: :pull_request_source
    @fork = create(:fork_repository, forker: @bwalsh, fork_repo: @source, from_example: :pull_request_fork)

    @issue1          = create :issue, repository: @source, user: @ryan
    @issue1_comment1 = create :issue_comment, issue: @issue1, user: @ryan
    @issue1_comment2 = create :issue_comment, issue: @issue1, user: @ari

    @issue2          = create :issue, repository: @source, user: @bwalsh, state: "closed"
    @issue2_comment1 = create :issue_comment, issue: @issue2, user: @ryan

    @pr_issue   = create :issue, repository: @source, user: @bwalsh
    @pr_comment = create :issue_comment, issue: @pr_issue, user: @vince

    @pr = create :pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @pr_issue,
        user: @bwalsh

    @pr_issue.pull_request = @pr

    @pr_reivew_comment = create :pull_request_review_comment, pull_request: @pr, user: @ryan
  end

  context "finding issues" do
    test "includes issues created by the user" do
      assert_equal Set.new([@issue1.id, @issue2.id]), @ryan.interacted_issue_ids
      assert_equal Set.new([@issue2.id]), @bwalsh.interacted_issue_ids
    end

    test "includes issues commented on by the user" do
      assert_equal Set.new([@issue1.id]), @ari.interacted_issue_ids
      assert_equal Set.new, @vince.interacted_issue_ids
    end

    test "correct when exactly BATCH_SIZE issues" do
      test_batch_size = 5

      User::InteractionsDependency.stub_const(:BATCH_SIZE, test_batch_size) do
        expected_issues = Set.new([@issue1.id, @issue2.id])
        (test_batch_size - expected_issues.size).times do
          issue = create :issue, repository: @source, user: @ryan
          expected_issues << issue.id
        end

        assert_equal expected_issues, @ryan.interacted_issue_ids
      end
    end

    test "correct when BATCH_SIZE + 1 issues" do
      test_batch_size = 5

      User::InteractionsDependency.stub_const(:BATCH_SIZE, test_batch_size) do
        expected_issues = Set.new([@issue1.id, @issue2.id])
        (test_batch_size - expected_issues.size + 1).times do
          issue = create :issue, repository: @source, user: @ryan
          expected_issues << issue.id
        end

        assert_equal expected_issues, @ryan.interacted_issue_ids
      end
    end

    test "no issues" do
      test_user = create :user, login: "test"
      assert test_user.interacted_issue_ids.empty?
    end
  end

  context "finding pull requests" do
    test "includes pull requests created by the user" do
      assert_equal Set.new([@pr.id]), @bwalsh.interacted_pull_request_ids
    end

    test "includes pull requests commented on by the user" do
      assert_equal Set.new([@pr.id]), @vince.interacted_pull_request_ids
    end

    test "includes pull requests with review comments from the user" do
      assert_equal Set.new([@pr.id]), @ryan.interacted_pull_request_ids
    end

    test "correct when exactly BATCH_SIZE pull requests" do
      test_batch_size = 5

      User::InteractionsDependency.stub_const(:BATCH_SIZE, test_batch_size) do
        expected_prs = Set.new([@pr.id])
        (test_batch_size - 1).times do
          pr = create_pr
          expected_prs << pr.id
        end

        assert_equal expected_prs, @bwalsh.interacted_pull_request_ids
      end
    end

    test "correct when BATCH_SIZE + 1 requests" do
      test_batch_size = 5

      User::InteractionsDependency.stub_const(:BATCH_SIZE, test_batch_size) do
        expected_prs = Set.new([@pr.id])
        test_batch_size.times do
          pr = create_pr
          expected_prs << pr.id
        end

        assert_equal expected_prs, @bwalsh.interacted_pull_request_ids
      end
    end

    test "no issues" do
      test_user = create :user, login: "test"
      assert test_user.interacted_pull_request_ids.empty?
    end
  end

  private def create_pr
    create :pull_request, :disable_disk_access, repository: @source, user: @bwalsh, head_ref: rand(36**5).to_i.to_s(36)
  end
end
