# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryOpenIssueCountForTest < GitHub::TestCase
  fixtures do
    @repo  = create(:repository)
    @owner = @repo.owner
  end

  test "excludes closed issues" do
    create(:issue, repository: @repo, title: "Open issue", state: "open")
    create(:issue, repository: @repo, title: "Closed issue", state: "closed")

    assert_equal 2, @repo.issues.count
    assert_equal 1, @repo.open_issue_count_for(@owner)
  end

  test "excludes issues belonging to pull requests" do
    example_repo :simple, @repo

    create(:issue, repository: @repo, title: "Issue without a pull request", state: "open")
    create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "cr-line-endings",
      issue: create(:issue,
        repository: @repo,
        title: "Issue with a pull request",
        state: "open",
      ),
    )

    assert_equal 2, @repo.issues.count
    assert_equal 1, @repo.open_issue_count_for(@owner)
  end

  test "respects the :limit argument" do
    3.times { create(:issue, repository: @repo, state: "open") }

    assert_equal 3, @repo.issues.count
    assert_equal 3, @repo.open_issue_count_for(@owner)

    # The method ends up adding 1 to the limit so that the results can tell us
    # if the limit was crossed or not. See
    # https://github.com/github/github/pull/44952 for more background.
    assert_equal 2, @repo.open_issue_count_for(@owner, limit: 1)
  end

  test "respects manually setting the count" do
    3.times { create(:issue, repository: @repo, state: "open") }

    assert_equal 3, @repo.issues.count
    @repo.set_open_issue_count_for(@owner, 6000)
    assert_equal 5001, @repo.open_issue_count_for(@owner)

    @repo.set_open_issue_count_for(@owner, 5)
    assert_equal 5, @repo.open_issue_count_for(@owner)
  end

  test "respects the :limit argument when manually setting the count" do
    3.times { create(:issue, repository: @repo, state: "open") }

    assert_equal 3, @repo.issues.count
    @repo.set_open_issue_count_for(@owner, 5, limit: 1)
    assert_equal 2, @repo.open_issue_count_for(@owner, limit: 1)
    @repo.set_open_issue_count_for(@owner, 5, limit: 4)
    assert_equal 5, @repo.open_issue_count_for(@owner, limit: 4)
  end

  context "#async_commits_path_uri" do
    test "with no filter" do
      assert_equal "/#{@repo.owner.login}/#{@repo.name}/commits", @repo.async_commits_path_uri.sync.to_s
    end

    test "with an authors filter" do
      assert_equal "/#{@repo.owner.login}/#{@repo.name}/commits?author=bart", @repo.async_commits_path_uri(author: "bart").sync.to_s
    end
  end
end
