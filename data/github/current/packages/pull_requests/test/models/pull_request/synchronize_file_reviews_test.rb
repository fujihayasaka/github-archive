# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestSynchronizeDismissStaleFileReviewsOnPushTest < GitHub::TestCase
  include HydroTestHelpers
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @owner = create(:user, login: "ari")
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)
    @forker = create(:user, login: "bwalsh")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :pull_request_fork)

    @reviewer = create(:user, login: "reviewer1")
    @source.add_member @reviewer, action: :write

    @issue = create(:issue, user: @forker, repository: @source)

    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "#{@fork.user}:topic",
      user: @issue.user,
      issue: @issue)

    @owner.reviewed_files.create(filepath: "file10", pull_request_id: @pull.id, head_sha: @pull.head_sha)
    @reviewer.reviewed_files.create(filepath: "file10", pull_request_id: @pull.id, head_sha: @pull.head_sha)

    @file_review = @owner.reviewed_files.create(filepath: "file8", pull_request_id: @pull.id, head_sha: @pull.head_sha)
    @file_review2 = @reviewer.reviewed_files.create(filepath: "file8", pull_request_id: @pull.id, head_sha: @pull.head_sha)

    @owner.reviewed_files.create(filepath: "file9", pull_request_id: @pull.id, head_sha: @pull.head_sha)
    @reviewer.reviewed_files.create(filepath: "file9", pull_request_id: @pull.id, head_sha: @pull.head_sha)
  end

  setup do
    reset_repo_root
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    @pull.create_merge_commit
  end

  def commit_changes_to_pull
    with_enqueued_pr_sync_jobs do
      @fork.refs.find("topic").append_commit({
        message: "Commit on topic",
        committer: @forker,
      }, @forker) do |files|
        files.add("file8", "A new line")
      end
    end

    @pull.reload
  end

  test "dismisses all file reviews when new changes are commited to the file on the PR" do
    assert_equal 6, @pull.user_reviewed_files.not_dismissed.count
    assert_equal 0, @pull.user_reviewed_files.dismissed.count

    commit_changes_to_pull

    assert_equal 4, @pull.user_reviewed_files.not_dismissed.count
    assert_equal 2, @pull.user_reviewed_files.dismissed.count
    assert_same_elements %w[file10 file9], @pull.user_reviewed_files.not_dismissed.map(&:filepath).uniq
  end

  test "publishes a hydro event", skip_enterprise: true do
    commit_changes_to_pull

    assert_hydro_messages(count: 2, schema: "github.v1.MarkFileAsViewed")
  end

  test "defaults to no stale reviews when codeowners information is unavailable" do
    parent_sha = @pull.head_sha

    commit_changes_to_pull

    assert_equal 4, @pull.user_reviewed_files.not_dismissed.count
    assert_equal 2, @pull.user_reviewed_files.dismissed.count
    assert_same_elements %w[file10 file9], @pull.user_reviewed_files.not_dismissed.map(&:filepath).uniq

    @pull.user_reviewed_files.dismissed.update_all(dismissed: false)

    assert_equal 6, @pull.user_reviewed_files.not_dismissed.count
    assert_equal 0, @pull.user_reviewed_files.dismissed.count

    assert_equal ["file8"], @pull.stale_file_reviews(before: parent_sha, after: @pull.head_sha).map(&:filepath).uniq

    @pull.stubs(:codeowners_paths_load_error?).returns(true)

    assert_empty @pull.stale_file_reviews(before: parent_sha, after: @pull.head_sha)
  end
end

class PullRequestSynchronizeDismissStaleFileReviewsOnChangeBaseTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @source = create(:repository, owner: @owner, from_example: :pull_request_source)


    @issue = create(:issue, user: @owner, repository: @source)

    forward = @source.refs.find("master-forward-2")
    forward.append_commit({ message: "Commit", committer: @owner }, @owner) do |files|
      files.add("new_file1", "New file")
    end

    more_files_ref = @source.refs.create("refs/heads/more_files", forward.target_oid, @owner)
    more_files_ref.append_commit({ message: "Commit", committer: @owner }, @owner) do |files|
      files.add("new_file2", "New file 2")
    end

    @pull = PullRequest.create_for(@source,
      base: "master",
      head: "more_files",
      user: @issue.user,
      issue: @issue,
    )
    @owner.reviewed_files.create!(filepath: "new_file1", pull_request_id: @pull.id, head_sha: @pull.head_sha)
    @owner.reviewed_files.create!(filepath: "new_file2", pull_request_id: @pull.id, head_sha: @pull.head_sha)
  end

  test "dismisses file reviews if base changes and file is no longer included in pull request" do
    Spokesd.enable_spokesd

    assert_equal 2, @pull.user_reviewed_files.not_dismissed.count
    assert_equal 0, @pull.user_reviewed_files.dismissed.count

    @pull.change_base_branch(@owner, "master-forward-2")

    assert_equal 1, @pull.user_reviewed_files.not_dismissed.count
    assert_equal 1, @pull.user_reviewed_files.dismissed.count
  end
end
