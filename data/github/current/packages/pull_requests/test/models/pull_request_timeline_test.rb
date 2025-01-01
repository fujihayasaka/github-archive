# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestTimelineTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @repo = create(:repository, owner: @user)

    @issue = create(:issue, user: @user, repository: @repo, body: "whatever")
  end

  setup do
    reset_cache
    reset_repo_root

    example_repo :rebase_pull_request, @repo
  end

  test "keeps commits consistently in order even over a rebase" do
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: @issue,
    )
    refute_nil @pull.issue
    @issue.pull_request = @pull
    create :issue_comment, issue: @issue

    expected = %w(
      519f51fbf3bd01896f4139ad7d024dcd2e60df3a
      da6581939cb4ac68fb841d32091e0ac2e44a2d3a
      325d95e767aca5bf139ea7ce4904e8baedfe3d0d
      3064ee927ec225577854c0669b7362c2ae008621
      1968aab83ed37699fbc463d9f3ef40158ee597a4
      41016384a953942424cbd10008c85b4500a33a52
    )

    commits = @pull.changed_commits
    result = commits.collect(&:sha)

    assert_equal expected, result
  end

  test "keeps commits in timeline consistently in order even over a rebase" do
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: @issue,
    )
    refute_nil @pull.issue
    @issue.pull_request = @pull
    create :issue_comment, issue: @issue

    expected = %w(
      519f51fbf3bd01896f4139ad7d024dcd2e60df3a
      da6581939cb4ac68fb841d32091e0ac2e44a2d3a
      325d95e767aca5bf139ea7ce4904e8baedfe3d0d
      3064ee927ec225577854c0669b7362c2ae008621
      1968aab83ed37699fbc463d9f3ef40158ee597a4
      41016384a953942424cbd10008c85b4500a33a52
    )

    timeline = @pull.timeline_for(@user)
    commits = timeline.select { |d| d.is_a?(Platform::Models::PullRequestCommit) }.map(&:commit)
    result = commits.collect(&:oid)

    assert_equal expected, result
  end

  test "respects reordering rebases" do
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "wacky",
      issue: @issue,
    )
    refute_nil @pull.issue
    @issue.pull_request = @pull
    create :issue_comment, issue: @issue

    expected =
      %w(
        06936d8fc81e2eff94a8e85c08c643a4ebc549f8
        b6a9cfb9505d032f34a4dff46a4ffc8381ece1b4
        0e0d1f3a3a6beeb44a8d495c060a8807a9df9aac
      )

    commits = @pull.changed_commits
    result = commits.collect(&:sha)

    assert_equal expected, result
  end

  test "keeps commits in timeline consistently in order even over a reordering rebase" do
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "wacky",
      issue: @issue,
    )
    refute_nil @pull.issue
    @issue.pull_request = @pull
    create :issue_comment, issue: @issue

    expected =
      %w(
        06936d8fc81e2eff94a8e85c08c643a4ebc549f8
        b6a9cfb9505d032f34a4dff46a4ffc8381ece1b4
        0e0d1f3a3a6beeb44a8d495c060a8807a9df9aac
      )

    timeline = @pull.timeline_for(@user)
    commits = timeline.select { |d| d.is_a?(Platform::Models::PullRequestCommit) }.map(&:commit)
    result = commits.collect(&:oid)

    assert_equal expected, result
  end
end
