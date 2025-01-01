# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/pull_requests"

class PullRequestStateTest < GitHub::TestCase
  include GitHub::PullRequestTestHelpers

  fixtures do
    @user = create(:user)
    @pull = make_pr_and_repos
    @source_repo = @pull.repository
    @owner = @make_pr_repo_owner

    @closer = create(:user)
    @closed_pull = make_pr_and_repos
    @closed_pull.repository.add_member(@closer)
    @closed_pull.issue.close(@closer)

    @org_on_business_plus = create :business_plus_organization
    @org_repo = create :repository, owner: @org_on_business_plus
  end

  context "#async_closable_by" do
    test "author can close" do
      assert @pull.issue.async_closable_by?(@pull.user).sync
    end

    test "non-collaborator cannot close" do
      refute @pull.issue.async_closable_by?(@user).sync
    end

    test "collaborator can close" do
      @source_repo.add_member(@user)
      assert @pull.issue.async_closable_by?(@user).sync
    end

    test "triage role can close" do
      org_repo = create :repository, owner: @org_on_business_plus, from_example: :pull_request_source
      pull = make_pr(org_repo, @pull.head_repository)
      org_repo.send(:grant, @user, :triage)

      assert pull.issue.async_closable_by?(@user).sync
    end
  end

  context "#reopenable?" do
    test "cannot reopen a pull request if head has been detached from base" do
      GitHub.flipper[:check_cross_repo_in_reopenable].enable

      repo = create :repository, owner: @owner, from_example: :pull_request_source
      fork_repo = create :fork_repository, forker: @closer, fork_repo: repo, from_example: :pull_request_fork

      closed_pull = make_pr(repo, fork_repo)
      closed_pull.close(@owner)
      assert closed_pull.reopenable?

      fork_repo.detach!(synchronous: true)

      assert closed_pull.cross_repo_violation?
      refute closed_pull.reload.reopenable?
    end
  end

  context "#reopenable_by" do
    test "author can reopen" do
      assert @closed_pull.issue.reopenable_by?(@closed_pull.user)
    end

    test "non-collaborator cannot reopen" do
      refute @closed_pull.issue.reopenable_by?(@user)
    end

    test "closer can reopen" do
      assert @closed_pull.issue.reopenable_by?(@closed_pull.closed_by)
    end

    test "collaborator can reopen" do
      @closed_pull.repository.add_member(@user)
      assert @closed_pull.issue.reopenable_by?(@user)
    end

    test "triage role can reopen" do
      org_repo = create :repository, owner: @org_on_business_plus, from_example: :pull_request_source
      fork_repo = create :fork_repository, forker: @owner, fork_repo: org_repo, from_example: :pull_request_fork

      closed_pull = make_pr(org_repo, fork_repo)
      closer = create(:user)
      closed_pull.repository.add_member(closer)
      closed_pull.issue.close(closer)

      org_repo.send(:grant, @user, :triage)

      assert closed_pull.issue.reopenable_by?(@user)
    end
  end
end
