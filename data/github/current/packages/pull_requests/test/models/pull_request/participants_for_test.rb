# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestParticipantsForTest < GitHub::TestCase
  include PullRequestSynchronizationTestHelpers

  fixtures do
    Spokesd.enable_spokesd

    @repo_owner = create(:user, login: "repo-owner")
    @forker     = create(:user, login: "forker")
    @other_user = create(:user, login: "goodguy", name: "Bob", email: "goodguy@blah.com")
    @spammer    = create(:user, login: "spammyguy", spammy: true)

    @repo = create(:repository, owner: @repo_owner)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @repo)

    @issue_owner = @forker
    @issue  =
      create(:issue,
        user: @issue_owner,
        repository: @repo,
        body: "gotta fix this",
      )
  end

  setup do
    reset_cache
    reset_repo_root

    example_repo :pull_request_source, @repo
    example_repo :pull_request_fork,   @fork

    @pull =
      PullRequest.new(
        repository: @repo,
        base_repository: @repo,
        base_user: @repo_owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @forker,
        user: @issue_owner,
        head_ref: "topic",
        issue: @issue,
        status: "open",
      )

    refute_nil @pull.issue
    @issue.pull_request = @pull

    @pull.save!

    @head = @fork.refs.find("topic")
    @commit = @head.target_oid
  end

  test "list of participants includes Pull Request's Issue owner" do
    assert_equal [@issue_owner], @pull.participants_for(@repo_owner)
  end

  test "list of participants includes commenters on the Pull Request" do
    create :issue_comment, issue: @issue, body: "hello!", user: @other_user
    assert_same_elements [@issue_owner, @other_user],
      @pull.participants_for(@repo_owner)
  end

  test "list of participants includes review commenters" do
    comment = create :pull_request_review_comment, pull_request: @pull, user: @other_user, body: "rad!"
    comment.submit!
    assert_same_elements [@issue_owner, @other_user],
      @pull.participants_for(@repo_owner)
  end

  test "list of participants doesn't authors of pending reviews" do
    create :pull_request_review_comment, pull_request: @pull, user: @other_user, body: "rad!"
    assert_same_elements [@issue_owner],
      @pull.participants_for(@repo_owner)
  end

  test "list of participants includes commit participants (people with commit comments)" do
    create :commit_comment, user: @other_user, repository: @fork,
      position: 0, path: "color.js", commit_id: @commit

    assert_same_elements [@issue_owner, @other_user],
      @pull.participants_for(@repo_owner)
  end

  test "list of participants includes event actors" do
    create :issue_event, issue: @issue, event: "merged", actor_id: @other_user.id
    assert_same_elements [@issue_owner, @other_user],
      @pull.participants_for(@repo_owner)
  end

  test "list of participants includes commit authors" do
    meta = { message: "commit this!", committer: @other_user }
    commit = @fork.commits.create(meta, @commit) do |files|
      files.add("my_new_file.txt", "check this out!\n")
    end

    with_enqueued_pr_sync_jobs do
      @head.update(commit, @other_user)
    end
    @pull.reload

    assert_same_elements [@issue_owner, @other_user],
      @pull.participants_for(@repo_owner)
  end

  test "list of participants does not include mentioners of Pull Request or its Issue from other Issues" do
    create(:issue, repository: @pull.base_repository).comments.create!({
      repository: @pull.repository,
      user: @other_user,
      body: "this must have to do with ##{@pull.number}",
    })

    assert_equal [@issue_owner], @pull.participants_for(@repo_owner)
  end

  if GitHub.spamminess_check_enabled?
    test "list of participants does not include spammers" do
      # spammer is going to try to do one of everything to get noticed...
      create :issue_comment, issue: @issue, body: "spam!", user: @spammer
      create(:pull_request_review_comment,
        pull_request: @pull,
        user: @spammer,
        body: "spam!",
        commit_id: @pull.head_sha,
        path: "file10",
        original_position: 1,
      )
      create :commit_comment, user: @spammer, repository: @fork,
        position: 0, path: "color.js", commit_id: @commit
      create :issue_event, issue: @issue, event: "assigned", actor: @spammer, subject: @spammer, assignee: @spammer

      # have spammer also make a commit
      meta = { message: "commit this!", committer: @spammer }
      commit = @fork.commits.create(meta, @commit) do |files|
        files.add("my_new_file.txt", "check this out!\n")
      end

      with_enqueued_pr_sync_jobs do
        @head.update(commit, @spammer)
      end
      @pull.reload

      assert_equal [@issue_owner], @pull.participants_for(@repo_owner)
      assert_equal [@issue_owner, @spammer], @pull.participants_for(@spammer)
    end
  end
end
