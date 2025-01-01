# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequests::Copilot::CodeReviewThreadNameGeneratorTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :commits_controller_test)
    @pull = PullRequest.create_for(@repo, base: @repo.default_branch, head: "topic", user: @user,
      title: "Please enjoy my code changes")
    @forker = create(:user, login: "IForkRepos")
    @forked_repo = create(:fork_repository, from_example: :commits_controller_test, forker: @forker, fork_repo: @repo)
  end

  setup do
    @base_branch_name = @repo.default_branch
    @head_branch_name = "topic"
    @base_ref = @repo.refs.find(@base_branch_name)
    @head_ref = @repo.refs.find(@head_branch_name)
    @start_commit, @end_commit = @pull.compare_repository.commits.find([@base_ref.sha, @head_ref.sha])
  end

  context ".call" do
    test "returns a thread name for a pull request comparison" do
      pull_comparison = PullRequest::Comparison.new(pull: @pull, start_commit: @start_commit, end_commit: @end_commit,
        base_commit: @start_commit)

      result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: pull_comparison)

      assert_equal "#{@user.display_login}/#{@repo.name} #{@head_branch_name} review " \
        "(#{@start_commit.abbreviated_oid}..#{@end_commit.abbreviated_oid})", result
    end

    test "returns a thread name for a comparison" do
      comparison = GitHub::Comparison.from_range(@repo, "#{@base_branch_name}..#{@head_branch_name}")

      result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: comparison)

      assert_equal "#{@user.display_login}/#{@repo.name} #{@head_branch_name} review " \
        "(#{comparison.base_commit.abbreviated_oid}..#{comparison.head_commit.abbreviated_oid})", result
    end

    test "returns a thread name for a pull request" do
      result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(pull_request: @pull)

      assert_equal "#{@user.display_login}/#{@repo.name} #{@head_branch_name} review " \
        "(#{@start_commit.abbreviated_oid}..#{@end_commit.abbreviated_oid})", result
    end

    test "returns a thread name when given neither pull request nor comparison" do
      assert_equal PullRequests::Copilot::CodeReviewThreadNameGenerator::DEFAULT_NAME,
        PullRequests::Copilot::CodeReviewThreadNameGenerator.call
    end

    test "returns a thread name when given a pull request comparison that has no pull request" do
      pull_comparison = PullRequest::Comparison.new(pull: @pull, start_commit: @start_commit, end_commit: @end_commit,
        base_commit: @start_commit)
      PullRequest::Comparison.any_instance.stubs(:pull).returns(nil)

      result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: pull_comparison)

      assert_equal PullRequests::Copilot::CodeReviewThreadNameGenerator::DEFAULT_NAME, result
    end

    test "returns a thread name when base repository does not exist" do
      @repo.delete
      result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(pull_request: @pull.reload)
      assert_equal PullRequests::Copilot::CodeReviewThreadNameGenerator::DEFAULT_NAME, result
    end

    test "returns a thread name when head repository does not exist" do
      head_ref = @forked_repo.refs.find(@head_branch_name)
      refute_nil head_ref
      cross_repo_pull = PullRequest.create_for(@repo, base: @repo.default_branch,
        head: "#{@forker}:#{@forked_repo.name}:#{@head_branch_name}", user: @forker, title: "a cross-repo PR")
      @forked_repo.delete

      result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(pull_request: cross_repo_pull.reload)

      assert_equal "#{@user.display_login}/#{@repo.name} #{@head_branch_name} review " \
        "(#{@base_ref.commit.abbreviated_oid}..#{head_ref.commit.abbreviated_oid})", result
    end

    test "returns a thread name for a cross-repository comparison" do
      fork_comparison = GitHub::Comparison.from_range(@repo,
        "#{@repo.default_branch}..#{@forker}:#{@forked_repo.name}:#{@head_branch_name}")
      head_ref = @forked_repo.refs.find(@head_branch_name)
      refute_nil head_ref

      result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: fork_comparison)

      assert_equal "#{@user.display_login}/#{@repo.name} #{@head_branch_name} review " \
        "(#{@base_ref.commit.abbreviated_oid}..#{@forker.display_login}:#{@forked_repo.name}:" \
        "#{head_ref.commit.abbreviated_oid})", result
    end

    test "different base shas result in different thread names" do
      other_commit = @repo.commits.history(@base_ref.sha, max = 1, skip = 1).first
      refute_nil other_commit
      refute_equal other_commit.oid, @base_ref.sha, "need a different git ref than the base branch"

      comparison1 = GitHub::Comparison.from_range(@repo, "#{@base_branch_name}..#{@head_branch_name}")
      result1 = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: comparison1)

      comparison2 = GitHub::Comparison.from_range(@repo, "#{other_commit.oid}..#{@head_branch_name}")
      result2 = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: comparison2)

      refute_equal result1, result2
    end

    test "different head shas result in different thread names" do
      other_commit = @repo.commits.history(@base_ref.sha, max = 1, skip = 1).first
      refute_nil other_commit
      refute_equal other_commit.oid, @head_ref.sha, "need a different git ref than the head branch"

      comparison1 = GitHub::Comparison.from_range(@repo, "#{@base_branch_name}..#{@head_branch_name}")
      result1 = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: comparison1)

      comparison2 = GitHub::Comparison.from_range(@repo, "#{@base_branch_name}..#{other_commit.oid}")
      result2 = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: comparison2)

      refute_equal result1, result2
    end

    test "different head repositories result in different thread names" do
      fork_comparison1 = GitHub::Comparison.from_range(@repo,
        "#{@repo.default_branch}..#{@forker}:#{@forked_repo.name}:#{@head_branch_name}")

      other_forker = create(:user, login: "IAlsoForkRepos")
      other_forked_repo = create(:fork_repository, from_example: :commits_controller_test, forker: other_forker,
        fork_repo: @repo)
      fork_comparison2 = GitHub::Comparison.from_range(@repo,
        "#{@repo.default_branch}..#{other_forker}:#{other_forked_repo.name}:#{@head_branch_name}")

      result1 = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: fork_comparison1)
      result2 = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: fork_comparison2)

      refute_equal result1, result2
    end

    test "comparisons and pull request for the same code range produce the same name" do
      pull_comparison = PullRequest::Comparison.new(pull: @pull, start_commit: @start_commit, end_commit: @end_commit,
        base_commit: @start_commit)
      comparison = GitHub::Comparison.from_range(@repo, "#{@base_branch_name}..#{@head_branch_name}")

      pull_result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(pull_request: @pull)
      pull_comparison_result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: pull_comparison)
      comparison_result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: comparison)

      assert_equal pull_result, pull_comparison_result, "expected thread name for a PullRequest::Comparison to " \
        "match that for the same PullRequest"
      assert_equal pull_result, comparison_result, "expected thread name for a GitHub::Comparison and a " \
        "PullRequest for the same diff to be the same"
    end

    test "comparisons and pull request for the same cross-repository code range produce the same name" do
      head_ref = @forked_repo.refs.find(@head_branch_name)
      refute_nil head_ref
      cross_repo_pull = PullRequest.create_for(@repo, base: @repo.default_branch,
        head: "#{@forker}:#{@forked_repo.name}:#{@head_branch_name}", user: @forker, title: "a cross-repo PR")
      start_commit, end_commit = cross_repo_pull.compare_repository.commits.find([@base_ref.sha, head_ref.sha])
      cross_repo_pull_comparison = PullRequest::Comparison.new(pull: cross_repo_pull, start_commit: start_commit,
        end_commit: end_commit, base_commit: start_commit)
      fork_comparison = GitHub::Comparison.from_range(@repo,
        "#{@repo.default_branch}..#{@forker}:#{@forked_repo.name}:#{@head_branch_name}")

      cross_repo_pull_result = PullRequests::Copilot::CodeReviewThreadNameGenerator
        .call(pull_request: cross_repo_pull)
      cross_repo_pull_comparison_result = PullRequests::Copilot::CodeReviewThreadNameGenerator
        .call(comparison: cross_repo_pull_comparison)
      fork_comparison_result = PullRequests::Copilot::CodeReviewThreadNameGenerator.call(comparison: fork_comparison)

      assert_equal cross_repo_pull_result, cross_repo_pull_comparison_result,
        "expected thread name for a PullRequest::Comparison to match that for the same PullRequest"
      assert_equal cross_repo_pull_result, fork_comparison_result,
        "expected thread name for a GitHub::Comparison and a PullRequest for the same diff to be the same"
    end
  end
end
