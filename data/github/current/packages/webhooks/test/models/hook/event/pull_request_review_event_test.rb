# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventPullRequestReviewEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org = create(:organization)
    @user = create(:user)
    @reviewer = create(:user)
    @repo = create :repository, owner: @org, from_example: :rebase_pull_request
    @repo.add_member @user
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
    @pr_review = create :pull_request_review, pull_request: @pull, user: @reviewer

    @copilot_review_bot = create(:copilot_pull_request_reviewer_integration).bot
    @copilot_review = create(:pull_request_review, pull_request: @pull, user: @copilot_review_bot)
  end

  test "require attributes" do
    assert_event_required_attributes Hook::Event::PullRequestReviewEvent,
      :action, :pull_request_review_id
  end

  context "#pull_request_review" do
    test "returns the specified review" do
      event = Hook::Event::PullRequestReviewEvent.new action: :submitted, pull_request_review_id: @pr_review.id
      assert_equal @pr_review, event.pull_request_review
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified review" do
      event = Hook::Event::PullRequestReviewEvent.new action: :submitted, pull_request_review_id: @pr_review.id
      assert_equal @repo, event.target_repository
    end
  end

  context "#actor" do
    test "returns the creator if no actor_id is present" do
      event = Hook::Event::PullRequestReviewEvent.new action: :submitted, pull_request_review_id: @pr_review.id
      assert_equal @reviewer, event.actor
    end

    test "returns the actor if an actor_id is present" do
      event = Hook::Event::PullRequestReviewEvent.new action: :submitted, pull_request_review_id: @pr_review.id, actor_id: @user.id
      assert_equal @user, event.actor
    end
  end

  context "#model_importing?" do
    test "returns true when the repo locked for migration" do
      @repo.lock_for_migration
      event = Hook::Event::PullRequestReviewEvent.new action: :submitted, pull_request_review_id: @pr_review.id, actor_id: @user.id
      assert event.model_importing?
      assert_predicate event, :model_importing?
    end

    test "returns false when the repo locked for migration" do
      event = Hook::Event::PullRequestReviewEvent.new action: :submitted, pull_request_review_id: @pr_review.id, actor_id: @user.id
      refute event.model_importing?
      refute_predicate event, :model_importing?
    end
  end

  context "#copilot code review" do
    test "does not queue for copilot review without comments" do
      DeliverHookEventJob.expects(:perform_later).never
      Hook::Event::PullRequestReviewEvent.queue(action: :submitted, actor_id: @copilot_review_bot.id, pull_request_review_id: @copilot_review.id)
    end

    test "queues for copilot review with comments" do
      thread = @pull.review_threads.build(pull_request_review: @copilot_review)
      thread.build_first_comment(body: "ship it", path: "README", line: 1,).save!
      @copilot_review.comment!

      DeliverHookEventJob.expects(:perform_later).once
      Hook::Event::PullRequestReviewEvent.queue(action: :submitted, actor_id: @copilot_review_bot.id, pull_request_review_id: @copilot_review.id)
    end
  end
end
