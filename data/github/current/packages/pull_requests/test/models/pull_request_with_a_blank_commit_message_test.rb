# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestWithABlankCommitMessageTest < GitHub::TestCase
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
        head_ref: "master-plus-blank-commit-message",
        head_sha: "ba1d261cfb3f4db16e438bf1b83e3308bb57302e",
        issue: @issue,
        user: @fork.owner,
      )
  end

  test "default commit messages are ok with a commit that has a blank commit message" do
    assert_equal 1, @pull.changed_commits.size
    assert_equal "Merge pull request #1 from #{@fork.owner}/master-plus-blank-commit-message", @pull.default_merge_commit_title
    assert_equal "#{@pull.title} (##{@pull.number})", @pull.default_squash_commit_title
    assert_equal <<~MSG.chomp, @pull.default_squash_commit_message
      Co-authored-by: Scott J. Goldman <scottjg@github.com>
      MSG
  end

  test "invalid pull requests should not throw exceptions on `valid?`" do
    User.create_ghost

    # We know the record is invalid, we just want to make sure no weird exceptions are thrown
    # in the process of coming to that conclusion.
    refute PullRequest.new.valid?
  end

  test "can lock a PR even if issues are disabled" do
    @pull.repository.update_attribute(:has_issues, false)

    assert @pull.issue.lock(@pull.repository.owner)
    assert @pull.locked?
  end
end
