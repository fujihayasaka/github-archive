# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestWithOnlyASingleNonmergeCommitTest < GitHub::TestCase
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
        head_ref: "master-plus-one-commit",
        head_sha: "6dfa887193a5219c8bb8037ee9ba4f4feec51f4e",
        issue: @issue,
        user: @fork.owner,
      )
  end

  test "default commit messages uses PR title when only a single non-merge commit" do
    @pull.repository.set_squash_merge_commit_title_setting(setting: Configurable::SquashMergeCommitTitle::PR_TITLE, actor: @pull.repository.owner)

    assert_equal 1, @pull.changed_commits.size
    assert_equal "Merge pull request #1 from #{@fork.owner}/master-plus-one-commit", @pull.default_merge_commit_title
    assert_equal "#{@pull.title} (##{@pull.number})", @pull.default_squash_commit_title
    assert_equal <<~MSG.chomp, @pull.default_squash_commit_message
      add a file

      this commit message has multiple lines
      hopefully it's formatted correctly by github
      otherwise that would be a pretty annoying bug.

      Co-authored-by: Scott J. Goldman <scottjg@github.com>
      MSG
  end

  test "default squash commit title uses commit title when only a single non-merge commit" do
    @pull.repository.set_squash_merge_commit_title_setting(setting: Configurable::SquashMergeCommitTitle::COMMIT_OR_PR_TITLE, actor: @pull.repository.owner)

    assert_equal 1, @pull.changed_commits.size
    commit = @pull.changed_commits.first.message.lines.first.rstrip
    assert_equal "#{commit} (##{@pull.number})", @pull.default_squash_commit_title
  end

  test "default squash commit title uses PR title when only a single non-merge commit and Use PR Title setting enabled" do
    @pull.repository.set_squash_merge_commit_title_setting(setting: Configurable::SquashMergeCommitTitle::PR_TITLE, actor: @pull.repository.owner)

    assert_equal 1, @pull.changed_commits.size
    assert_equal "#{@pull.title} (##{@pull.number})", @pull.default_squash_commit_title
  end

  test "default squash commit message is blank if Use Blank setting enabled" do
    @pull.repository.set_squash_merge_commit_message_setting(setting: Configurable::SquashMergeCommitMessage::BLANK, actor: @pull.repository.owner)

    assert_equal 1, @pull.changed_commits.size
    assert_equal <<~MSG.chomp, @pull.default_squash_commit_message
      Co-authored-by: Scott J. Goldman <scottjg@github.com>
      MSG
  end

  test "default squash commit message uses PR body when only a single non-merge commit and Use PR Body setting enabled" do
    @pull.repository.set_squash_merge_commit_message_setting(setting: Configurable::SquashMergeCommitMessage::PR_BODY, actor: @pull.repository.owner)

    assert_equal 1, @pull.changed_commits.size
    assert_equal <<~MSG.chomp, @pull.default_squash_commit_message
      #{@pull.body_text}

      Co-authored-by: Scott J. Goldman <scottjg@github.com>
      MSG
  end

  test "default squash commit title omits PR title in message" do
    @pull.repository.set_squash_merge_commit_title_setting(setting: Configurable::SquashMergeCommitTitle::PR_TITLE, actor: @pull.repository.owner)

    assert_equal 1, @pull.changed_commits.size
    merge_commit, first_real_commit = @pull.merging_one_commit?
    @pull.issue.title = first_real_commit.message.lines.first.strip
    assert_equal "#{@pull.title} (##{@pull.number})", @pull.default_squash_commit_title
    assert_equal <<~MSG.chomp, @pull.default_squash_commit_message
      this commit message has multiple lines
      hopefully it's formatted correctly by github
      otherwise that would be a pretty annoying bug.

      Co-authored-by: Scott J. Goldman <scottjg@github.com>
      MSG
  end
end
