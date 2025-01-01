# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventPullRequestEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:user)
    @reviewer = create(:user)
    @repo = create :repository, owner: @user, from_example: :rebase_pull_request
    @issue = create(:issue, user: @user, repository: @repo)
    @pull = create(:pull_request,
      repository: @repo,
      base_repository: @repo,
      base_user: @repo.owner,
      base_ref: "master",
      head_repository: @repo,
      head_user: @repo.owner,
      head_ref: "contrib",
      issue: @issue,
    )
    @changes = {
      old_body: "Body",
      body: "Changed Body",
    }

    @owner = create(:user, login: "owner", plan: "micro")
    @business = create(:business)
    @org = create(:organization, login: "acme", business: @business, admin: @owner)
    @team = create(:team, organization: @org, name: "myteam", permission: "pull")
    @org_repo = create :repository, owner: @org, from_example: :rebase_pull_request
    @org_issue = create :issue, user: @user, repository: @org_repo
    @org_pull = create(:pull_request,
      repository: @org_repo,
      base_repository: @org_repo,
      base_user: @org_repo.owner,
      base_ref: "master",
      head_repository: @org_repo,
      head_user: @org_repo.owner,
      head_ref: "contrib",
      issue: @org_issue,
    )
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::PullRequestEvent, :action, :pull_request_id
  end

  context "missing repo" do
    test "when a repo is missing the job will not raise an exception" do
      repo_id = @org_repo.id
      @org_repo.delete
      assert_nil Repository.find_by(id: repo_id)

      # Attempt to process a "closed" event of the PR
      # This can happen as a result of a time race between the destruction jobs
      ProcessEventJob.perform_now("PullRequestEvent", [:closed, @org_pull.id, @user.id])
    end
  end

  context "destroyed org" do
    test "PullRequestEvent can be processed when the backing org is missing" do
      # Get rid of the org without the PR noticing
      org_id = @org.id
      @org.delete
      assert_nil Organization.find_by(id: org_id)

      # Attempt to process an `unassignment` of the PR
      # This can and will happen as a result of the org's destruction and the async nature
      # of the jobs that result from the destruction.
      ProcessEventJob.perform_now("PullRequestEvent", [:unassigned, @org_pull.id, @user.id, assignee_id: @user.id])
    end
  end

  context "#pull_request" do
    test "returns the specified pull_request" do
      event = Hook::Event::PullRequestEvent.new action: :submitted, pull_request_id: @pull.id, actor_id: @user.id
      assert_equal @pull, event.pull_request
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified user" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id, actor_id: @user.id
      assert_equal @pull.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id, actor_id: @user.id
      assert_equal @user, event.actor
    end

    test "returns the author of the pull request if no actor is specified" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id
      assert_equal @pull.user, event.actor
    end
  end

  context "#review_requested" do
    test "returns the specified reviewer" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id, actor_id: @user.id, subject_id: @reviewer.id, subject_type: "User"
      assert_equal @reviewer, event.requested_reviewer
    end

    test "returns the specified team" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id, actor_id: @user.id, subject_id: @team.id, subject_type: "Team"
      assert_equal @team, event.requested_reviewer
    end

    test "nil returned if no reviewer is specified" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id, actor_id: @user.id
      assert_nil event.requested_reviewer
    end
  end

  context "#before" do
    test "returns the specified before SHA" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id, actor_id: @user.id, before: @pull.base_sha, after: @pull.head_sha
      assert_equal @pull.base_sha, event.before
    end
  end

  context "#after" do
    test "returns the specified after SHA" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id, actor_id: @user.id, before: @pull.base_sha, after: @pull.head_sha
      assert_equal @pull.head_sha, event.after
    end
  end

  context "#reason" do
    test "returns the specified reason for auto-merge being disabled" do
      event = Hook::Event::PullRequestEvent.new action: :auto_merge_disabled, pull_request_id: @pull.id, actor_id: @user.id, reason: "Pull request was closed"
      assert_equal "Pull request was closed", event.reason
    end
  end

  context "#deliverable?" do
    test "returns true when the action is created" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id
      assert_predicate event, :deliverable?
    end

    test "returns true when the action is edited" do
      event = Hook::Event::PullRequestEvent.new action: :edited, pull_request_id: @org_pull.id, changes: @changes
      assert_predicate event, :deliverable?
    end

    test "returns false when the PR and target_repository are no longer available" do
      event = Hook::Event::PullRequestEvent.new action: :edited, pull_request_id: -1, changes: @changes
      refute_predicate event, :deliverable?
    end
  end

  context "#model_importing?" do
    test "returns true when the repo locked for migration" do
      @repo.lock_for_migration
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id
      assert event.model_importing?
      assert_predicate event, :model_importing?
    end

    test "returns false when the repo is not locked for migration" do
      event = Hook::Event::PullRequestEvent.new action: :created, pull_request_id: @pull.id
      refute event.model_importing?
      refute_predicate event, :model_importing?
    end
  end

  context ".description" do
    test "returns the right description" do
      assert_equal "Pull request assigned, auto merge disabled, auto merge enabled, closed, converted to draft, demilestoned, dequeued, edited, enqueued, labeled, locked, milestoned, opened, ready for review, reopened, review request removed, review requested, synchronized, unassigned, unlabeled, or unlocked.",
        Hook::Event::PullRequestEvent.description
    end
  end

  context ".changes" do
    test "returns body change when change" do
      changes = {
        old_body: "old body",
        body: "new body",
      }

      event = Hook::Event::PullRequestEvent.new action: :edited, pull_request_id: @pull.id, actor_id: @user.id, changes: changes

      expected_changes = { body: { from: "old body" } }

      assert event.changes
      assert_equal expected_changes, event.changes
    end

    test "returns body change when empty" do
      changes = {
        old_body: "old body",
        body: "",
      }

      event = Hook::Event::PullRequestEvent.new action: :edited, pull_request_id: @pull.id, actor_id: @user.id, changes: changes

      expected_changes = { body: { from: "old body" } }

      assert event.changes
      assert_equal expected_changes, event.changes
    end

    test "returns body change when nil" do
      changes = {
        old_body: "old body"
      }

      event = Hook::Event::PullRequestEvent.new action: :edited, pull_request_id: @pull.id, actor_id: @user.id, changes: changes

      expected_changes = { body: { from: "old body" } }

      assert event.changes
      assert_equal expected_changes, event.changes
    end
  end

  test "extra attributes should be deleted and not raise error" do
    GitHub.flipper[:prehydrate_primary_webhook_data_for_pull_request].enable
    extra_attributes = { super_fake_attribute: "bad data to break AR!" }
    primary_resource_data = @pull.attributes.merge(extra_attributes)
    event = Hook::Event::PullRequestEvent.new(action: "created", pull_request_id: @pull.id, primary_resource_data: primary_resource_data)
  end

  def create_pull_request
    repo = create(:repository, owner: @org, from_example: :pull_request_source)
    pull = PullRequest.create_for!(repo, title: "hello", user: @owner, base: "master", head: "master-forward-2")
  end
end
