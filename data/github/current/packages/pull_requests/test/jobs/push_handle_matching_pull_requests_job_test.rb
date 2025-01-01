# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class PushHandleMatchingPullRequestsJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @owner = create(:user, login: "owner",  plan: "medium")
    @repo = create(:repository, owner: @owner, name: "widgets", from_example: :rebase_pull_request)

    @pull = create :pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: create(:issue, repository: @repo, user: @owner),
      user: @defunkt

    @before = "325d95e767aca5bf139ea7ce4904e8baedfe3d0d"
    @after = "1968aab83ed37699fbc463d9f3ef40158ee597a4"
    @ref = "refs/heads/contrib"
  end

  setup do
    clear_enqueued_jobs
  end

  test "job retries" do
    arguments = [@repo.id, @before, @after, @ref, Time.now, @owner]
    assert_retry_on_error(ActiveRecord::ConnectionTimeoutError, PushHandleMatchingPullRequestsJob, arguments)
    assert_retry_on_error(ActiveRecord::QueryCanceled, PushHandleMatchingPullRequestsJob, arguments)
    assert_retry_on_error(ActiveRecord::RecordNotFound, PushHandleMatchingPullRequestsJob, arguments)
  end

  test "job enqueues auto-merge job for open pull requests" do
    PullRequest.any_instance.expects(:enqueue_auto_merge_job_if_enabled).once

    PushHandleMatchingPullRequestsJob.perform_now(@repo.id, before: @before, after: @after, ref: @ref, pushed_at: Time.now, pusher: @owner)
  end

  test "sends notifications for matching open pull requests" do
    GitHub.newsies.expects(:trigger).once

    PushHandleMatchingPullRequestsJob.perform_now(@repo.id, before: @before, after: @after, ref: @ref, pushed_at: Time.now, pusher: @owner)
  end

  test "does not send notification if repository is missing" do
    GitHub.newsies.expects(:trigger).never
    Repository.delete(@pull.repository.id)
    @pull.reload

    PushHandleMatchingPullRequestsJob.perform_now(@repo.id, before: @before, after: @after, ref: @ref, pushed_at: Time.now, pusher: @owner)
  end
end

class MatchingOpenPullRequestsTest < GitHub::TestCase
  fixtures do
    @defunkt = create(:user, login: "defunkt",  plan: "medium")
    @repo = create(:repository, owner: @defunkt, name: "widgets", from_example: :rebase_pull_request)

    @org_admin = create(:user)
    @org = create(:organization, admin: @org_admin, plan: "business")
    @org_repo = create(:repository, owner: @org, name: "widgets", from_example: :rebase_pull_request)

    @fork_repo = create(:fork_repository, forker: @org_admin, fork_repo: @repo, from_example: :rebase_pull_request)

    # some tests modify repo, so restore to this point before each test
    example_repo_snapshot

    @pull = create :pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: create(:issue, repository: @repo, user: @defunkt),
      user: @defunkt

    @before = "325d95e767aca5bf139ea7ce4904e8baedfe3d0d"
    @after = "1968aab83ed37699fbc463d9f3ef40158ee597a4"
    @ref = "refs/heads/contrib"
  end

  teardown do
    # restore repo snapshot to reset changes
    example_repo_restore
  end

  test "finds open PRs whose head ref matches the branch being pushed to" do
    @pull.close

    # Open another PR for the contrib branch
    pull2 = create :pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: create(:issue, repository: @repo, user: @defunkt),
      user: @defunkt

    other_pull = create :pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "wacky",
      issue: create(:issue, repository: @repo, user: @defunkt),
      user: @defunkt

    job = PushHandleMatchingPullRequestsJob.perform_later(@repo.id, before: @before, after: @after, ref: @ref, pushed_at: Time.now, pusher: @defunkt)
    matching_pulls = []
    T.unsafe(job).matching_open_pull_requests_to_update(@repo.id, @ref, @before, @after) do |pull_request|
      matching_pulls << pull_request
    end
    assert_same_elements [pull2], matching_pulls
  end

  test "excludes fork PRs that have a base repository that has been soft deleted" do
    fork_pull = create :pull_request,
      repository: @fork_repo,
      base_repository: @fork_repo,
      base_user: @fork_repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: create(:issue, repository: @fork_repo, user: @defunkt),
      user: @defunkt

    orchestration = RepositoryOrchestration.delete(@fork_repo, actor: @fork_repo.owner)
    orchestration.execute(synchronous: true)

    job = PushHandleMatchingPullRequestsJob.perform_later(@repo.id, before: @before, after: @after, ref: @ref, pushed_at: Time.now, pusher: @defunkt)

    matching_pulls = []
    T.unsafe(job).matching_open_pull_requests_to_update(@repo.id, @ref, @before, @after) do |pull_request|
      matching_pulls << pull_request
    end
    assert_same_elements [@pull], matching_pulls
  end

  test "excludes pulls if the before oid is not included in the PR's changed commits" do
    nonexistent_oid = "242413806a5ccd2c04b587c4300621e8e1ca54c6"

    job = PushHandleMatchingPullRequestsJob.perform_later(@repo.id, before: nonexistent_oid, after: @after, ref: @ref, pushed_at: Time.now, pusher: @defunkt)

    matching_pulls = []
    T.unsafe(job).matching_open_pull_requests_to_update(@repo.id, @ref, nonexistent_oid, @after) do |pull_request|
      matching_pulls << pull_request
    end

    assert_empty matching_pulls
  end

  test "excludes pulls whose after is null oid" do
    job = PushHandleMatchingPullRequestsJob.perform_later(@repo.id, before: @before, after: GitHub::NULL_OID, ref: @ref, pushed_at: Time.now, pusher: @defunkt)

    matching_pulls = []
    T.unsafe(job).matching_open_pull_requests_to_update(@repo.id, @ref, @before, GitHub::NULL_OID) do |pull_request|
      matching_pulls << pull_request
    end

    assert_empty matching_pulls
  end

  test "excludes pulls for which the diff hasn't changed" do
    job = PushHandleMatchingPullRequestsJob.perform_later(@repo.id, before: @before, after: @before, ref: @ref, pushed_at: Time.now, pusher: @defunkt)

    matching_pulls = []
    T.unsafe(job).matching_open_pull_requests_to_update(@repo.id, @ref, @before, @before) do |pull_request|
      matching_pulls << pull_request
    end

    assert_empty matching_pulls
  end

  test "returns no PRs if the push is for a merge from base to head" do
    # create a new commit in the base ref
    base_ref = @pull.base_repository.heads.find(@pull.base_ref)
    base_owner = @pull.base_repository.owner
    base_ref.append_commit({ message: "Add to base branch", committer: base_owner }, base_owner) do |files|
      files.add("blah.txt", "some conflicting contents")
    end

    # merge the latest base ref into the head ref
    head_ref = @pull.head_repository.heads.find(@pull.head_ref)
    base_owner = @pull.base_repository.owner
    base_ref.merge(base_owner, @pull.base_ref)

    # Simulate a push of the merge commit
    merge_commit = base_ref.target
    job = PushHandleMatchingPullRequestsJob.perform_later(@repo.id, before: merge_commit.parent_oids[0], after: merge_commit.oid, ref: @ref, pushed_at: Time.now, pusher: @defunkt)

    matching_pulls = []
    T.unsafe(job).matching_open_pull_requests_to_update(@repo.id, @ref, merge_commit.parent_oids[0], merge_commit.oid) do |pull_request|
      matching_pulls << pull_request
    end

    assert_empty matching_pulls
  end

  test "returns no PRs if the diff is between two unrelated commits" do
    commit = @repo.commits.create({ committer: @repo.owner, message: "Orphaned Commit" }) do |files|
      files.add("Readme.md", "Orphaned Commit")
    end

    job = PushHandleMatchingPullRequestsJob.perform_later(@repo.id, before: @before, after: commit.oid, ref: @ref, pushed_at: Time.now, pusher: @defunkt)

    matching_pulls = []
    T.unsafe(job).matching_open_pull_requests_to_update(@repo.id, @ref, @before, commit.oid) do |pull_request|
      matching_pulls << pull_request
    end

    assert_empty matching_pulls
  end

  if GitHub.spamminess_check_enabled?
    test "excludes open PRs from a spammy author" do
      spammer = create(:user, login: "spammer")
      spammer.mark_as_spammy

      # set PR author as spammer
      @pull.issue.update(user: spammer)
      @pull.update(user: spammer)

      # verify the PR is marked as spammy
      assert_predicate @pull, :spammy?

      job = PushHandleMatchingPullRequestsJob.perform_later(@repo.id, before: @before, after: @after, ref: @ref, pushed_at: Time.now, pusher: @defunkt)

      matching_pulls = []
      T.unsafe(job).matching_open_pull_requests_to_update(@repo.id, @ref, @before, @after) do |pull_request|
        matching_pulls << pull_request
      end

      assert_empty matching_pulls
    end
  end
end
