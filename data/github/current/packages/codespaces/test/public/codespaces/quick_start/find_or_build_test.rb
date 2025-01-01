# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::QuickStart::FindOrBuildTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user, from_example: :simple_default_main)
  end

  test "returns existing codespace when resumable one is found" do
    codespace = create(:codespace, owner: @user, repository: @repo)
    result = Codespaces::QuickStart::FindOrBuild.call(owner: @user, repository: @repo)

    assert_equal codespace, result
  end

  test "returns a new codespace when none are found" do
    result = Codespaces::QuickStart::FindOrBuild.call(owner: @user, repository: @repo)

    refute result.provisioned?
    assert result.new_record?
    assert_equal @repo.default_branch, result.ref
    assert_equal @repo, result.repository
    assert_equal @user, result.owner
  end

  test "uses the default branch when creating a new codespace with a non-existent ref" do
    result = Codespaces::QuickStart::FindOrBuild.call(owner: @user, repository: @repo, ref: "bogus-branch")

    assert_equal @repo.default_branch, result.ref
  end

  test "uses the supplied ref when creating a new codespace if it exists" do
    result = Codespaces::QuickStart::FindOrBuild.call(owner: @user, repository: @repo, ref: "-gh-pages")

    assert_equal "-gh-pages", result.ref
  end

  test "uses the provided pull request when creating a new codespace" do
    forker = create(:user)
    fork = create(:fork_repository, forker: forker, fork_repo: @repo)
    pull = create(:pull_request, :disable_disk_access, repository: @repo, base_repository: @repo, head_repository: fork)
    result = Codespaces::QuickStart::FindOrBuild.call(owner: forker, repository: @repo, pull_request: pull)

    refute result.ref
    assert_equal pull, result.pull_request
    assert_equal pull.head_repository, result.repository
  end
end
