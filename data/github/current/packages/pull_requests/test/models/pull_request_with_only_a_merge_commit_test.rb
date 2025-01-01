# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestWithOnlyAMergeCommitTest < GitHub::TestCase
  fixtures do
    @source  = create(:repository)
    @forker  = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source)
  end

  setup do
    reset_cache
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    @issue =
      create(:issue,
        user: @forker,
        repository: @source,
        body: "hey @vince look at this real quick",
      )

    @pull =
      PullRequest.new(
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        base_sha: "a270ea0fdfba2bd5a33934e5184784cddce87f38",
        head_user: @fork.owner,
        head_repository: @fork,
        head_ref: "merge-commit-only",
        head_sha: "e9bdc31d05097054356885483b68fc0cbc0e1e33",
        issue: @issue,
        user: @fork.owner,
      )
  end

  test "default commit messages are ok when only merging a merge commit" do
    assert_equal 1, @pull.changed_commits.size
    assert_equal "Merge pull request #1 from #{@fork.owner}/merge-commit-only", @pull.default_merge_commit_title
    assert_equal "#{@pull.title} (##{@pull.number})", @pull.default_squash_commit_title
    assert_equal <<~MSG.chomp, @pull.default_squash_commit_message
      Co-authored-by: Scott J. Goldman <scottjg@github.com>
      MSG
  end
end
