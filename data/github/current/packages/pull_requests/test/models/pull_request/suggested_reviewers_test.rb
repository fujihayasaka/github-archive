# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestSuggestedReviewersTest < GitHub::TestCase
  include DogstatsTestHelpers
  include PerformanceTestHelpers

  fixtures do
    @owner = create(:user, plan: "micro")
    @committer = create(:user)
    @reviewer = create(:user)
    @suspended_reviewer = create(:user)

    @repo, @old_pull_same_branch, @commit = create_pull_request(@owner, @committer, "topic-branch")
    @old_pull_same_branch.close
    @pull = make_pull(@repo, "topic-branch")

    @recent_commenter = create(:user)
    @opinionated_reviewer = create(:user)
    @opinionated_reviewer2 = create(:user)
    @old_commenter = create(:user)
    @other_path_commenter = create(:user)

    # Candidate users are collaborators.
    @repo.add_member(@committer, action: :write)
    @repo.add_member(@reviewer, action: :write)
    @repo.add_member(@suspended_reviewer, action: :write)
    @repo.add_member(@recent_commenter, action: :write)
    @repo.add_member(@opinionated_reviewer, action: :write)
    @repo.add_member(@opinionated_reviewer2, action: :write)
    @repo.add_member(@old_commenter, action: :write)
    @repo.add_member(@other_path_commenter, action: :write)

    @commit.freeze

    @copilot_app = create(:copilot_pull_request_reviewer_integration)
  end

  setup do
    Spokesd.enable_spokesd
  end

  test "adds copilot when eligible" do
    PullRequests::Copilot::CodeReviewAccess.any_instance.stubs(:should_suggest_reviewer?).returns(true)
    subject = PullRequest::SuggestedReviewers.new(@pull)
    suggestions = subject.find(excluding: @committer)
    assert_equal [@copilot_app.bot, @repo.owner, @reviewer], suggestions.map(&:user)
  end

  test "ranks suggested reviewers by contribution age" do
    subject = PullRequest::SuggestedReviewers.new(@pull)
    suggestions = subject.find(excluding: @committer)
    assert_equal [@repo.owner, @reviewer], suggestions.map(&:user)
  end

  test "commits_for_paths makes 2 gitrpc calls per file" do
    GitHub::Experiment.raise_on_mismatches = false

    subject = PullRequest::SuggestedReviewers.new(@pull)
    deltas = subject.send(:diff_deltas)
    paths = subject.send(:paths_for_deltas, deltas)

    assert_git_rpc_calls(count: (TestEnv.test_all_features? ? 0 : 2) + (paths.count * 2)) do
      subject.send(:commits_for_paths, paths)
    end
  end

  test "commits_for_paths_time_bound makes 1 gitrpc calls per file" do
    GitHub::Experiment.raise_on_mismatches = false

    subject = PullRequest::SuggestedReviewers.new(@pull)
    deltas = subject.send(:diff_deltas)
    paths = subject.send(:paths_for_deltas, deltas)

    assert_git_rpc_calls(count: (TestEnv.test_all_features? ? 0 : 1) + (paths.count * 1)) do
      subject.send(:commits_for_paths_time_bound, paths)
    end
  end

  test "doesn't suggest suspended users as reviewers" do
    comment(@old_pull_same_branch, @suspended_reviewer, "changes.txt", 1.second.ago, :changes_requested)
    @suspended_reviewer.suspend "Reasons"
    subject = PullRequest::SuggestedReviewers.new(@pull)
    suggestions = subject.find(excluding: @committer)
    assert_equal [@repo.owner, @reviewer], suggestions.map(&:user)
  end

  test "is available for non-fork repositories" do
    subject = PullRequest::SuggestedReviewers.new(@pull)
    assert_predicate subject, :available?
  end

  test "ranks commenters by comment age" do
    # Comment on these paths in a different pull request.
    comment(@old_pull_same_branch, @old_commenter, "changes.txt", 5.years.ago, :approved)
    comment(@old_pull_same_branch, @recent_commenter, "changes.txt", 1.second.ago, :commented)
    comment(@old_pull_same_branch, @opinionated_reviewer, "changes.txt", 1.second.ago, :changes_requested)
    comment(@old_pull_same_branch, @committer, "changes.txt", 1.second.ago, :approved)
    comment(@old_pull_same_branch, @other_path_commenter, "a-new-file.txt", 1.second.ago, :approved)

    # Comment in this pull request should be ignored by suggestions.
    comment(@pull, @opinionated_reviewer2, "changes.txt", 1.second.ago, :changes_requested)

    subject = PullRequest::SuggestedReviewers.new(@pull)
    suggestions = subject.find(excluding: @committer)
    assert_equal [@opinionated_reviewer, @repo.owner, @reviewer], suggestions.map(&:user)
  end

  test "allows passing limit to restrict the count of returned suggestions" do
    subject = PullRequest::SuggestedReviewers.new(@pull)

    assert_equal [@repo.owner], subject.find(limit: 1).map(&:user)
  end

  test "allows passing limit as nil to receive all suggestions" do
    subject = PullRequest::SuggestedReviewers.new(@pull)

    assert_equal [@repo.owner, @reviewer], subject.find(limit: nil).map(&:user)
  end

  test "handles already loaded diff with path restructions" do
    # Calling pull.deletions will load a diff with path restrictions, throwing
    # a GitHub::Diff::AlreadyLoaded exception if we try to reuse the same diff
    # with a new path
    @pull.deletions

    subject = PullRequest::SuggestedReviewers.new(@pull)
    suggestions = subject.find(excluding: @committer)
    assert_equal [@repo.owner, @reviewer], suggestions.map(&:user)
  end

  test "filters by date" do
    subject = PullRequest::SuggestedReviewers.new(@pull, max_commit_age: 6.months)

    # @reviewer is filtered out by date
    assert_equal [@repo.owner], subject.find.map(&:user)
  end

  test "doesn't error if individual git blame times out" do
    enable_feature_flag(:iopromise_concurrent_blame)

    PullRequest::SuggestedReviewers.stub_const(:BLAME_TIMEOUT_SECONDS, 0.0000001) do
      subject = PullRequest::SuggestedReviewers.new(@pull)

      # no results are returned because the blame operation times out
      assert_equal [], subject.find.map(&:user)
    end
  end

  test "doesn't error if cumulative git blame operations time out" do
    enable_feature_flag(:iopromise_concurrent_blame)

    PullRequest::SuggestedReviewers.stub_const(:BLAME_CUMULATIVE_TIMEOUT_SECONDS, 0.0000001) do
      subject = PullRequest::SuggestedReviewers.new(@pull)

      # no results are returned because the blame operation times out
      assert_equal [], subject.find.map(&:user)
    end
  end

  test "doesn't error if blame fails due to bad .git-blame-ignore-revs file" do
    async_boom = Promise.new.tap do |promise|
      promise.reject GitRPC::InvalidIgnoreRevs.new
    end

    subject = PullRequest::SuggestedReviewers.new(@pull)
    if GitHub.flipper[:suggested_reviewers_blame_time_bound].enabled?
      subject.comparison.base_repo.rpc.expects(:blame).at_least_once.raises(GitRPC::InvalidIgnoreRevs.new)
    else
      subject.comparison.base_repo.rpc.expects(:async_blame).at_least_once.returns(async_boom)
    end

    # no results are returned because the blame fails
    assert_equal [], subject.find.map(&:user)
  end

  test "loads data from cache" do
    comment(@old_pull_same_branch, @old_commenter, "changes.txt", 5.years.ago, :approved)
    comment(@old_pull_same_branch, @recent_commenter, "changes.txt", 1.second.ago, :commented)
    comment(@old_pull_same_branch, @opinionated_reviewer, "changes.txt", 1.second.ago, :changes_requested)
    comment(@old_pull_same_branch, @committer, "changes.txt", 1.second.ago, :approved)
    comment(@old_pull_same_branch, @other_path_commenter, "a-new-file.txt", 1.second.ago, :approved)

    with_cache_enabled do
      subject = PullRequest::SuggestedReviewers.new(@pull)
      uncached_suggestions = subject.find(excluding: @committer)
      assert_same_elements [@opinionated_reviewer, @repo.owner, @reviewer], uncached_suggestions.map(&:user)
      assert_dogstats_timing("reviewers.cached", tags: ["type:miss"])

      subject = PullRequest::SuggestedReviewers.new(@pull)
      cached_suggestions = subject.find(excluding: @committer)
      assert_same_elements [@opinionated_reviewer, @repo.owner, @reviewer], cached_suggestions.map(&:user)
      assert_dogstats_timing("reviewers.cached", tags: ["type:hit"])

      assert_same_elements uncached_suggestions, cached_suggestions
    end
  end

  private

  # Comment frequently on a path so the user's commenter score is higher than
  # their blame author score.
  def comment(pull, user, path, created_at, state)
    3.times do
      review = pull.pending_review_for(user: user, head_sha: pull.head_sha)

      create(:pull_request_review_comment,
        pull_request: pull,
        user: user,
        commit_id: pull.head_sha,
        path: path,
        original_position: 1,
        body: "ship it",
        created_at: created_at,
        pull_request_review_id: review.id,
      )

      review.update!(state: state, body: "a review")
    end
  end

  def create_pull_request(owner, committer, branch)
    repo = create(:repository, owner: owner, from_example: :pull_request_source)

    repo.add_member(committer, action: :write)

    # Create commits to find in blame history.
    base_ref = repo.heads.find("master")

    # Reviewer commits two lines a long time ago.
    base_ref.
        append_commit({ message: "new file", committer: @reviewer, committed_date: 1.year.ago.utc.iso8601 },
                      repo.owner) { |files| files.add("changes.txt", "old 1\nold 2") }

    # Owner recently changes line two.
    base_ref.
        append_commit({ message: "new file", committer: repo.owner },
                      repo.owner) { |files| files.add("changes.txt", "old 1\nnew 2") }

    # Owner adds an empty file.
    base_ref.
        append_commit({ message: "empty file", committer: repo.owner },
                      repo.owner) { |files| files.add("empty.txt", "") }

    # Owner adds a binary file.
    base_ref.
        append_commit({ message: "binary file", committer: repo.owner },
                      repo.owner) { |files| files.add("binary.bin", "\x00#{SecureRandom.bytes(1024)}") }

    # Owner adds a file with one line.
    base_ref.
        append_commit({ message: "one line file", committer: repo.owner },
                      repo.owner) { |files| files.add("one-line.txt", "one line\n") }

    # Committer changes both lines and opens pull request.
    head_ref = repo.heads.create(branch, base_ref.target, committer)
    commit = head_ref.
        append_commit({ message: "please work", committer: committer },
                      committer) { |files| files.add("changes.txt", "new 1\nupdated 2") }

    # Committer adds a file that should be ignored by suggester.
    commit = head_ref.
        append_commit({ message: "please work", committer: committer },
                      committer) { |files| files.add("a-new-file.txt", "ignore this") }

    # Committer changes the empty file
    commit = head_ref.
        append_commit({ message: "change it", committer: committer },
                      committer) { |files| files.add("empty.txt", "some changes\n") }

    # Committer changes adds a line to the one-lined file
    commit = head_ref.
        append_commit({ message: "change it", committer: committer },
                      committer) { |files| files.add("one-line.txt", "one line\nanother line\n") }

    # Committer updates the binary file
    commit = head_ref.
        append_commit({ message: "update binary file", committer: committer },
                      committer) { |files| files.add("binary.bin", "\x00#{SecureRandom.bytes(1024)}") }

    pull = make_pull(repo, branch)
    [repo, pull, commit]
  end

  def make_pull(repo, branch)
    issue = create(:issue, repository: repo)
    create(:pull_request,
      repository: repo,
      base_repository: repo,
      base_user: repo.owner,
      base_ref: "master",
      head_repository: repo,
      head_user: repo.owner,
      head_ref: branch,
      issue: issue)
  end
end
