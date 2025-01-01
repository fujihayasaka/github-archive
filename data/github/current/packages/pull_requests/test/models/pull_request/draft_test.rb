# typed: true
# frozen_string_literal: true

require "test_helper"

class DraftPullRequestsTest < GitHub::TestCase
  include HookIntegrationTestHelper
  include HydroTestHelpers

  fixtures do
    @owner = create(:user, login: "abc")
    @org = create(:organization, admin: @owner)
    @team = create(:team, organization: @org, privacy: :closed)
    @collaborator = create(:user, login: "def")
    @team.add_member @collaborator, adder: @owner

    @repo = create(:repository, owner: @org, from_example: :pull_request_source)
    @repo.add_member(@collaborator)
    @team.add_repository(@repo, :push)

    contents = <<~OWNERS
        * @#{@owner}
    OWNERS
    base_ref = @repo.heads.find("master")
    base_ref.append_commit({ message: "codeowners", committer: @owner }, @owner) do |files|
      files.add("CODEOWNERS", contents)
    end
  end

  setup do
    @repo.stubs(:plan_supports?).with(:draft_prs).returns(true)
    @repo.stubs(:plan_supports?).with(:codeowners).returns(true)
    @repo.stubs(:plan_supports?).with(:team_review_requests).returns(true)
    @repo.stubs(:plan_supports?).with(:custom_key_links).returns(false)
    @repo.stubs(:plan_supports?).with(:protected_branches).returns(true)
  end

  test "doesn't request codeowners review when a Draft PR is opened" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft:   true,
    )

    assert pull.draft?, "PR should be marked as a draft"
    assert_equal 0, pull.review_requests.count, "PR should have 0 review requests"
  end

  test "requests codeowners review when Draft PR is marked as ready for review" do
    perform_enqueued_jobs(only: [RequestPullRequestReviewersJob]) do
      pull = PullRequest.create_for(@repo,
        user:  @collaborator,
        base:  "master",
        head:  "master-merged-topic",
        title: "test pr",
        body:  "a test pr",
        draft:   true,
      )
      assert pull.draft?, "PR should be marked as work in progress"
      assert_equal 0, pull.review_requests.count, "PR should have 0 review requests"

      pull.ready_for_review!(user: @collaborator)

      assert_equal 1, pull.review_requests.count, "PR should have 1 review request"
    end
  end

  test "creates an issue event when marked as ready for review" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft:   true,
    )

    assert_difference -> { pull.events.where(event: "ready_for_review").count } do
      pull.ready_for_review!(user: @collaborator)
    end
  end

  test "opens a normal PR if plan doesn't support draft prs" do
    @repo.stubs(:plan_supports?).with(:draft_prs).returns(false)
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft:   true,
    )

    refute pull.draft?
  end

  test "organizations with a legacy plan get the draft prs" do
    plan = GitHub::Plan.gold
    plan.stubs(:legacy?).returns(true)
    org = create(:organization, admin: @owner, plan: plan)
    repo = create(:repository, owner: org, created_by_user_id: @owner.id, from_example: :pull_request_source)
    repo.add_member(@collaborator)

    pull = PullRequest.create_for(repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft:   true,
    )

    assert pull.draft?
  end

  test "emits a webhook with the proper `draft` status when created" do
    perform_enqueued_jobs(only: [DeliverHookEventJob, IssueOrchestration.job_class]) do
      hook = create :hook, :web, installation_target: @repo, events: %w(pull_request)
      events = subscribe_to_hook_delivery "pull_request"
      PullRequest.create_for!(@repo,
                              user:  @collaborator,
                              base:  "master",
                              head:  "master-merged-topic",
                              title: "test pr",
                              body:  "a test pr",
                              draft: true,
                             )

      assert_equal 1, events.count
      payload = events.payload_for_hook(hook)
      assert payload[:pull_request][:draft]
    end
  end

  test "#convert_to_draft converts PR to draft" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft: false,
    )

    pull.convert_to_draft(user: @collaborator)
    assert pull.draft?
  end

  test "#convert_to_draft doesn't convert a closed PR to draft" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft: false,
    )

    pull.close(pull.user)

    pull.convert_to_draft(user: @collaborator)
    refute pull.reload.draft?
  end

  test "#ready_for_review marks deferred requests as ready when transitioning from draft" do
    perform_enqueued_jobs(only: [RequestPullRequestReviewersJob]) do
      reviewer = create(:user)
      @repo.add_member(reviewer)

      pull = PullRequest.create_for(@repo,
        user:  @collaborator,
        base:  "master",
        head:  "master-merged-topic",
        title: "test pr",
        body:  "a test pr",
        draft:   true,
      )
      assert pull.draft?, "PR should be marked as draft"

      assert_no_difference("pull.issue.events.count") do
        pull.review_requests.create!(reviewer: reviewer, deferred: true)
      end
      assert_equal 1, pull.review_requests.count, "PR should have 1 review request"

      assert_difference("pull.issue.events.count", 3) do
        pull.ready_for_review!(user: @collaborator)
      end

      pull.reload

      assert_equal 2, pull.review_requests.count, "PR should have 2 review request"

      review_request = pull.review_requests.ready.where(reviewer: reviewer).last
      assert review_request, "PR should have a review request for the deferred reviewer"
      request_event = pull.events.where(event: :review_requested, issue_event_detail: { subject: reviewer }).last
      assert request_event, "PR should have a review requested event for the deferred reviewer"
      assert_equal @collaborator, request_event.actor
      assert_equal T.must(review_request).id, request_event.review_request_id
    end
  end

  test "#ready_for_review marks deferred requests as ready when transitioning from in progress" do
    perform_enqueued_jobs(only: [RequestPullRequestReviewersJob]) do
      reviewer = create(:user)
      @repo.add_member(reviewer)

      pull = PullRequest.create_for(@repo,
        user:  @collaborator,
        base:  "master",
        head:  "master-merged-topic",
        title: "test pr",
        body:  "a test pr",
        draft:   true,
      )
      assert pull.draft?, "PR should be marked as draft"

      pull.in_progress_state!
      assert pull.in_progress_state?, "PR should be marked as work in progress"

      assert_no_difference("pull.issue.events.count") do
        pull.review_requests.create!(reviewer: reviewer, deferred: true)
      end
      assert_equal 1, pull.review_requests.count, "PR should have 1 review request"

      pull.save
      assert_difference("pull.issue.events.count", 3) do
        pull.ready_for_review!(user: @collaborator)
      end

      pull.reload

      assert_equal 2, pull.review_requests.count, "PR should have 2 review request"

      review_request = pull.review_requests.ready.where(reviewer: reviewer).last
      assert review_request, "PR should have a review request for the deferred reviewer"
      request_event = pull.events.where(event: :review_requested, issue_event_detail: { subject: reviewer }).last
      assert request_event, "PR should have a review requested event for the deferred reviewer"
      assert_equal @collaborator, request_event.actor
      assert_equal T.must(review_request).id, request_event.review_request_id
    end
  end

  test "ready_for_review does not automatically re-request reviews when transitioning from in_progress" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft: false,
    )
    pull.save
    pull.in_progress_state!

    pull.reviews.create!(
      user: @owner,
      head_sha: pull.head_sha,
      body: "an approval",
    ).approve!

    refute T.unsafe(pull.review_requests).pending.any?

    perform_enqueued_jobs(only: [RequestPullRequestReviewersJob]) do
      pull.save
      pull.ready_for_review!(user: @collaborator)
    end

    refute pull.reload.review_requests.pending.any?
  end

  test "#ready_for_review updates draft reviewable_state" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft: false,
    )
    pull.save
    pull.draft_state!

    assert_predicate pull, :draft?
    assert_predicate pull, :draft_state?

    pull.ready_for_review!(user: @collaborator)

    refute_predicate pull, :draft?
    assert_predicate pull, :ready_state?
  end

  test "#ready_for_review updates in_progress reviewable_state" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft: false,
    )
    pull.save
    pull.in_progress_state!

    refute_predicate pull, :draft?
    assert_predicate pull, :in_progress_state?

    pull.ready_for_review!(user: @collaborator)

    refute_predicate pull, :draft?
    assert_predicate pull, :ready_state?
  end

  test "#ready_for_review handles duplication between deferred requests and codeowners requests" do
    perform_enqueued_jobs(only: [RequestPullRequestReviewersJob]) do
      pull = PullRequest.create_for(@repo,
        user:  @collaborator,
        base:  "master",
        head:  "master-merged-topic",
        title: "test pr",
        body:  "a test pr",
        draft:   true,
      )
      assert pull.draft?, "PR should be marked as work in progress"

      assert_no_difference("pull.issue.events.count") do
        pull.review_requests.create!(reviewer: @owner, deferred: true)
      end
      assert_equal 1, pull.review_requests.count, "PR should have 1 review request"

      assert_difference("pull.issue.events.count", 2) do
        pull.ready_for_review!(user: @collaborator)
      end

      assert_equal 1, pull.review_requests.count, "PR should have 1 review request"

      review_request = pull.review_requests.last
      request_event = pull.events.last
      assert_equal "review_requested",  request_event.event
      assert_equal @owner,    request_event.subject
      assert_equal @collaborator, request_event.actor
      assert_equal T.must(review_request).id, request_event.review_request_id
    end
  end

  test "#ready_for_review doesn't make changes if the PR is already ready" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft:  false,
    )
    assert pull.ready_state?, "PR should be marked as ready"

    assert_no_changes -> { pull.events.where(event: :ready_for_review).count } do
      pull.ready_for_review!(user: @collaborator)
    end
  end

  test "#ready_for_review creates a ready_for_review event" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft:   true,
    )
    assert pull.draft?, "PR should be marked as a draft"

    pull.ready_for_review!(user: @collaborator)

    event = pull.events.last
    assert event, "A ready_for_review event should be created"

    assert_equal "ready_for_review", event.event
    assert_equal @collaborator, event.actor
  end

  test "#ready_for_review creates a ready_for_review event if the PR head hasn't changed" do
    pull = PullRequest.create_for(@repo,
      user:  @collaborator,
      base:  "master",
      head:  "master-merged-topic",
      title: "test pr",
      body:  "a test pr",
      draft:   true,
    )
    assert pull.draft?, "PR should be marked as a draft"

    pull.ready_for_review!(user: @collaborator)

    event = pull.events.last
    assert event, "A ready_for_review event should be created"

    assert_equal "ready_for_review", event.event
    assert_equal @collaborator, event.actor

    pull.convert_to_draft(user: @collaborator)
    pull.ready_for_review!(user: @collaborator)
    pull.reload

    new_event = pull.events.last
    refute_equal event, new_event, "A new ready_for_review event should be created"

    assert_equal "ready_for_review", new_event.event
    assert_equal @collaborator, new_event.actor
  end

  unless GitHub.enterprise?
    test "emits hydro events when Draft PR is marked as ready for review" do
      pull = PullRequest.create_for(@repo,
        user:  @collaborator,
        base:  "master",
        head:  "master-merged-topic",
        title: "test pr",
        body:  "a test pr",
        draft:   true,
      )
      assert pull.draft?, "PR should be marked as work in progress"
      assert_equal 0, pull.review_requests.count, "PR should have 0 review requests"
      pull.ready_for_review!(user: @collaborator)

      msg = {
        pull_request: Hydro::EntitySerializer.pull_request(pull),
        issue: Hydro::EntitySerializer.issue(pull.issue),
        actor: Hydro::EntitySerializer.user(@collaborator),
        repository: Hydro::EntitySerializer.repository(pull.repository),
        repository_owner: Hydro::EntitySerializer.user(T.must(pull.repository).owner),
        reviewable_state_was: "draft"
      }

      assert_hydro_published(msg, schema: "github.v1.PullRequestReadyForReview")
    end

    test "emits hydro events when a PR is converted to draft" do
      pull = PullRequest.create_for(@repo,
        user:  @collaborator,
        base:  "master",
        head:  "master-merged-topic",
        title: "test pr",
        body:  "a test pr",
        draft: false
      )
      refute pull.draft?, "PR should not be marked as work in progress"
      pull.convert_to_draft(user: @collaborator)

      msg = {
        pull_request: Hydro::EntitySerializer.pull_request(pull),
        issue: Hydro::EntitySerializer.issue(pull.issue),
        actor: Hydro::EntitySerializer.user(@collaborator),
        repository: Hydro::EntitySerializer.repository(pull.repository),
        repository_owner: Hydro::EntitySerializer.user(T.must(pull.repository).owner),
        reviewable_state_was: "ready"
      }

      assert_hydro_published(msg, schema: "github.v1.PullRequestConvertToDraft")
    end
  end
end
