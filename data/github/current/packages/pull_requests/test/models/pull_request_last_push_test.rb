# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestLastPushTest < GitHub::TestCase
  include GitHub::QueryAssertionTestHelpers

  fixtures do
    @owner = create(:user, plan: "pro")
    @org = create(:organization, admin: @owner)
    @repo = create(:repository, owner: @org, from_example: :review_comment_source)

    @forker = create(:user)
    @repo.add_member @forker, action: :write
    @forked = create(:fork_repository, forker: @forker, fork_repo: @repo, from_example: :review_comment_fork)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  def create_pull_request(ref: "topic1")
    head_branch = @repo.heads.create(ref, @repo.heads.find("master").target, @owner)
    metadata = { message: "update file1", committer: @owner }
    head_branch.append_commit(metadata, @owner) { |f| f.add "file1", "1" }
    after_oid = head_branch.target_oid

    PullRequest.create_for!(@repo,
      user: @owner,
      base: "master",
      head: ref,
      title: "testing pull request",
      body: "just some thing",
    )
  end

  def create_pull_request_on_fork
    PullRequest.create_for!(@repo,
      user: @forker,
      base: "#{@org.login}:master",
      head: "#{@forker.login}:rename-topic",
      title: "testing pull request",
      body: "just some thing",
    )
  end

  context "validations" do
    test "Sorbet" do
      pull = create_pull_request

      ex = assert_raises do
        last_push = PullRequestLastPush.new(repository: @repo, pull_request: pull, push_id: "foo", head_sha: "90abcdef" * 5)
      end
      assert ex.message.include?("'push_id': Expected type Integer")
    end

    test "ActiveRecord" do
      pull = create_pull_request

      last_push = PullRequestLastPush.new
      refute_predicate last_push, :valid?
      refute_empty last_push.errors[:pull_request] # required
      refute_empty last_push.errors[:repository] # required
      refute_empty last_push.errors[:push_id] # required
      assert_includes last_push.errors[:head_sha], "should be a full commit SHA"

      last_push = PullRequestLastPush.new(repository: @repo, pull_request: pull, push_id: 1234, head_sha: "x" * 40)
      refute_predicate last_push, :valid?
      assert_empty last_push.errors[:pull_request]
      assert_empty last_push.errors[:repository]
      assert_empty last_push.errors[:push_id]
      assert_includes last_push.errors[:head_sha], "should be a full commit SHA"

      last_push = PullRequestLastPush.new(repository: @repo, pull_request: pull, push_id: 1234, head_sha: "90abcdef" * 5)

      assert_predicate last_push, :valid?
      assert_empty last_push.errors[:pull_request]
      assert_empty last_push.errors[:repository]
      assert_predicate last_push.errors[:push_id], :empty?
      assert_predicate last_push.errors[:head_sha], :empty?
    end
  end

  context "database" do
    test "round-trip" do
      pull = create_pull_request
      assert_nil pull.last_push

      last_push = PullRequestLastPush.new(repository: @repo, pull_request: pull, push_id: 4321, head_sha: "90abcdef" * 5)

      assert_predicate last_push, :valid?
      last_push.save!

      pull.reload

      refute_nil pull.last_push

      assert_equal last_push.repository_id, pull.last_push.repository_id
      assert_equal last_push.pull_request_id, pull.last_push.pull_request_id
      assert_equal last_push.push_id, pull.last_push.push_id
      assert_equal last_push.head_sha, pull.last_push.head_sha
    end
  end

  context "finds correct push from last_push record" do
    test "on non-fork" do
      pull = create_pull_request
      user = pull.user

      repo = pull.repository
      head_repo = pull.head_repository
      head_branch = head_repo.heads[pull.head_ref]

      assert_nil pull.last_push

      before_oid = head_branch.target_oid

      metadata = { message: "msg", committer: user }
      head_branch.append_commit(metadata, user) { |f| f.add "file1", "1" }

      after_oid = head_branch.target_oid

      push1 = create :repositories_push, repository: head_repo, pusher: user, ref: pull.head_ref,
        before: before_oid, after: after_oid,
        created_at: 2.minutes.ago, pushed_at: 2.minutes.ago

      last_push = PullRequestLastPush.new(repository: repo, pull_request: pull, push_id: push1.id, head_sha: after_oid)
      last_push.save!

      pull.reload
      assert_equal pull.last_push.push, push1
    end

    test "on fork" do
      pull = create_pull_request_on_fork
      user = pull.user

      repo = pull.repository
      head_repo = pull.head_repository
      head_branch = head_repo.heads[pull.head_ref]

      assert_nil pull.last_push

      before_oid = head_branch.target_oid

      metadata = { message: "msg", committer: user }
      head_branch.append_commit(metadata, user) { |f| f.add "file1", "1" }

      after_oid = head_branch.target_oid

      push1 = create :repositories_push, repository: head_repo, pusher: user, ref: pull.head_ref,
        before: before_oid, after: after_oid,
        created_at: 2.minutes.ago, pushed_at: 2.minutes.ago

      last_push = PullRequestLastPush.new(repository: repo, pull_request: pull, push_id: push1.id, head_sha: after_oid)
      last_push.save!

      pull.reload
      assert_equal pull.last_push.push, push1
    end

    test "avoids table scans" do
      20.times do |i|
        pull = create_pull_request(ref: "topic#{i}")
        last_push = PullRequestLastPush.new(repository: @repo, pull_request: pull, push_id: 4321, head_sha: "90abcdef" * 5)
        last_push.save!
      end

      pull = @repo.pull_requests.first.reload

      refute_table_scans do
        pull.last_push
      end
    end
  end
end
