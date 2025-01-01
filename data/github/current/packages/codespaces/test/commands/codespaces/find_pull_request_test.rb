# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class FindPullRequestTest < GitHub::TestCase
    fixtures do
      @owner = create(:user)
      @repository = create(:repository, owner: @owner, from_example: :pull_request_source)
    end

    test "returns a PR for the owner on the specified ref" do
      pr_branch = "master-merged-topic"
      pull_request = create(:pull_request, user: @owner, repository: @repository, base_repository: @repository, head_repository: @repository, head_ref: pr_branch)
      found_pr = Codespaces::FindPullRequest.call(owner: @owner, repository: @repository, ref: pr_branch)
      assert_equal pull_request, found_pr
    end

    test "it returns nil when it cannot find a PR for the specified ref" do
      pr_branch = "master-merged-topic"
      pull_request = create(:pull_request, user: @owner, repository: @repository, base_repository: @repository, head_repository: @repository, head_ref: pr_branch)
      found_pr = Codespaces::FindPullRequest.call(owner: @owner, repository: @repository, ref: "not-the-pr-branch")
      refute found_pr
    end

    test "returns nil if multiple open PRs exist for the specified ref" do
      pr_branch = "master-merged-topic"
      pull1 = create(:pull_request, user: @owner, repository: @repository, base_repository: @repository, head_repository: @repository, head_ref: pr_branch)
      pull2 = create(:pull_request, user: @owner, repository: @repository, base_repository: @repository, head_repository: @repository, base_ref: "topic-partial-merge", head_ref: pr_branch)
      found_pr = Codespaces::FindPullRequest.call(owner: @owner, repository: @repository, ref: pr_branch)
      refute found_pr
    end

    test "returns the PR for the specified branch when the PR is from another user" do
      collaborator = create(:user)
      GitHub.flipper[:codespaces_unscoped_find_pr].enable(collaborator)
      @repository.add_member_without_validation_or_notifications(collaborator)
      pr_branch = "master-merged-topic"
      pull_request = create(:pull_request, user: @owner, repository: @repository, base_repository: @repository, head_repository: @repository, head_ref: pr_branch)
      found_pr = Codespaces::FindPullRequest.call(owner: collaborator, repository: @repository, ref: pr_branch)
      assert_equal pull_request, found_pr
    end

    test "returns nil if the ref is the repo's default branch" do
      pr_branch = @repository.default_branch
      pull_request = create(:pull_request, user: @owner, repository: @repository, base_repository: @repository, head_repository: @repository, base_ref: "conflicts", head_ref: pr_branch)
      found_pr = Codespaces::FindPullRequest.call(owner: @owner, repository: @repository, ref: pr_branch)
      refute found_pr
    end

    test "returns nil if repository argument is nil" do
      refute Codespaces::FindPullRequest.call(owner: create(:user), repository: nil, ref: "main")
    end

    test "returns nil if the user cannot push to the ref on the repository" do
      random_user = create(:user)
      pr_branch = "master-merged-topic"
      pull_request = create(:pull_request, user: @owner, repository: @repository, base_repository: @repository, head_repository: @repository, head_ref: pr_branch)
      found_pr = Codespaces::FindPullRequest.call(owner: random_user, repository: @repository, ref: pr_branch)
      refute found_pr
    end
  end
end
