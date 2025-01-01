# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class PullRequestNotificationSummaryTest < GitHub::TestCase
  fixtures do
    @source  = create(:repository)
    @forker  = create(:user)
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source)
    @owner  = create(:user, login: "owner", plan: "micro")

    @org = create :business_organization, login: "acme", admin: @owner
    @org_repo = create(:repository, owner: @org, from_example: :pull_request_source)
  end

  setup do
    reset_cache
    example_repo :pull_request_source, @source
    example_repo :pull_request_fork,   @fork

    only = [Newsies::DeliverNotificationsJob, SubscribeAndNotifyJob]
    perform_enqueued_jobs(only: only) do
      @pull = PullRequest.create_for!(@source,
        user: @forker,
        base: "#{@source.owner.login}:master",
        head: "#{@forker.login}:topic",
        title: "testing pull request",
        body: "just some thing",
      )
    end
    GitHub.flipper[:update_notification_summary_always_enqueue].enable
    GitHub.flipper[:update_notification_summary_with_locks].disable
  end

  def summary_for(pull)
    response = GitHub.newsies.web.find_rollup_summary_by_thread(pull.repository, pull.issue)
    response.value
  end

  test "starts off with an issue_state of 'open'" do
    assert_equal "open", summary_for(@pull).issue_state
  end

  test "updates issue_state properly when PR is closed and re-opened" do
    Spokesd.enable_spokesd

    perform_enqueued_jobs(only: [UpdateRollupSummaryStateJob]) do
      @pull.close
    end

    assert @pull.closed?
    assert_equal "closed", summary_for(@pull).issue_state

    perform_enqueued_jobs(only: [UpdateRollupSummaryStateJob]) do
      @pull.open(@source.owner)
    end

    assert @pull.open?
    assert_equal "open", summary_for(@pull).issue_state
  end

  test "updates issue_state to 'merged' when the PR is merged" do
    perform_enqueued_jobs(only: [UpdateNotificationSummaryJob]) do
      @pull.merge
    end
    assert @pull.merged?
    assert_equal "merged", summary_for(@pull).issue_state
  end

  test "has issue_state as 'merged' when the PR has been merged and then commented on" do
    perform_enqueued_jobs(only: [UpdateNotificationSummaryJob]) do
      @pull.merge
    end
    assert @pull.merged?

    perform_enqueued_jobs(only: [UpdateNotificationSummaryJob]) do
      @pull.issue.comments.create!(user: @forker, body: "glad you liked it")
    end
    assert_equal "merged", summary_for(@pull).issue_state
  end

  test "uses committer date from environment" do
    fake_ts = 1234567890
    Time.stubs(:now).returns(Time.at(fake_ts))
    assert(commit_oid = @pull.create_merge_commit)
    commit = @source.commits.find(commit_oid)
    assert_equal fake_ts, commit.committed_date.to_i
  end

  test "uses author date date from environment" do
    fake_ts = 1111111111
    Time.stubs(:now).returns(Time.at(fake_ts))
    assert(commit_oid = @pull.create_merge_commit)
    commit = @source.commits.find(commit_oid)
    assert_equal fake_ts, commit.authored_date.to_i
  end

  test "disallows PR creation for rando with no push access" do
    @pull.close
    rando = create(:user)

    exception = assert_raises(ActiveRecord::RecordInvalid) do
      pull = PullRequest.create_for(
              @source,
              user: rando,
              base: "master",
              head: "#{@fork.owner.login}:topic",
              title: "hewwo",
              body: "asdf",
            )
    end
    assert_equal exception.message, "Validation failed: must be a collaborator"
  end unless GitHub.enterprise?

  test "allows PR creation if no push access but member of org" do
    member = create(:user)
    @org.add_member(member)

    pull = PullRequest.create_for(
            @org_repo,
            user: member,
            base: "master",
            head: "master-merged-topic",
            title: "hewwo",
            body: "",
          )

    assert pull.persisted?
  end unless GitHub.enterprise?

  test "allows PR creation with read access granted to repo" do
    member = create(:user)
    @org_repo.add_member(member, action: :read)

    pull = PullRequest.create_for(
            @org_repo,
            user: member,
            base: "master",
            head: "master-merged-topic",
            title: "hewwo",
            body: "",
          )

    assert pull.persisted?
  end unless GitHub.enterprise?

  test "allows PR creation with triage access granted to repo" do
    member = create(:user)
    @org_repo.add_member(member, action: :triage)

    pull = PullRequest.create_for(
            @org_repo,
            user: member,
            base: "master",
            head: "master-merged-topic",
            title: "hewwo",
            body: "",
          )

    assert pull.persisted?
  end unless GitHub.enterprise?

  test "randos can create PRs in GHE" do
    @pull.destroy
    rando = create(:user)

    pull = PullRequest.create_for(
            @source,
            user: rando,
            base: "master",
            head: "#{@fork.owner.login}:topic",
            title: "hewwo",
            body: "",
          )

    assert pull.persisted?
  end if GitHub.enterprise?

  test "push access to head is enough for PR creation" do
    @pull.destroy
    pull = PullRequest.create_for(
            @source,
            user: @fork.owner,
            base: "master",
            head: "#{@fork.owner.login}:topic",
            title: "hewwo",
            body: "",
          )

    assert pull.persisted?
  end

  test "push access to base is enough for PR creation" do
    @pull.destroy
    pull = PullRequest.create_for(
            @source,
            user: @source.owner,
            base: "master",
            head: "#{@fork.owner.login}:topic",
            title: "hewwo",
            body: "",
          )

    assert pull.persisted?
  end
end
