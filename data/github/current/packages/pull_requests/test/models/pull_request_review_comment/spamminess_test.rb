# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewComment::SpamminessTest < GitHub::TestCase
  MENTION_LIMIT = GitHub::HTML::MentionFilter::MENTION_LIMIT

  fixtures do
    @owner    = create(:user, login: "owner")
    @spammer  = create(:user, login: "spammer", spammy: true)
    @source   = create(:repository, owner: @owner, from_example: :review_comment_source)
    @forker   = create(:user, login: "forker")
    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)
    @source.add_member @forker

    @issue = create(:issue, user: @forker, repository: @source)
    @pull =
      create(:pull_request,
        repository: @source,
        base_repository: @source,
        base_user: @source.owner,
        base_ref: "master",
        head_repository: @fork,
        head_user: @fork.owner,
        head_ref: "topic",
        issue: @issue,
        user: @forker,
      )
    @issue.pull_request = @pull

    @users = (0..(MENTION_LIMIT + 5)).map { |i| create :user, login: "user#{i}" }
    @users.first.watch_repo @source
    @users.last.watch_repo @source

    example_repo_snapshot
  end

  setup do
    skip "spamminess checks are not enabled on Enterprise" unless GitHub.spamminess_check_enabled?
    example_repo_restore
  end

  context "check_for_spam" do
    test "adds authors of spammy comments to Possible Spammer Queue" do
      comment = create(:pull_request_review_comment, pull_request: @pull)
      GitHub::SpamChecker.stubs(:test_comment).with(comment).returns("Spammy reason")
      GitHub::SpamChecker.stubs(:notify)
      GlobalInstrumenter.expects(:instrument).with(
        "add_account_to_spamurai_queue",
        {
          account_global_relay_id: comment.user.global_relay_id,
          additional_context: "RESQUE_CHECK_FOR_SPAM_PULL_REQUEST_REVIEW_COMMENT",
          origin: :RESQUE_CHECK_FOR_SPAM_PULL_REQUEST_REVIEW_COMMENT,
          queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
        },
      )

      comment.check_for_spam
    end
  end

  context "check_for_spam? properly controls whether to allow spam check" do
    setup do # rubocop:disable GitHub/NestedSetupTeardown
      @turtle = create(:user, login: "turtle", spammy: true)
    end

    test "check prrc with a normal user" do
      review = create(:pull_request_review, user: @users.first, pull_request: @pull)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: @users.first, pull_request_review: review, body: "hiya")

      assert review.comment!
      assert_predicate comment, :check_for_spam?
    end

    test "don't check prrc with no user" do
      comment = create(:pull_request_review_comment, pull_request: @pull)

      comment.user = nil
      refute_predicate comment, :check_for_spam?
    end

    test "don't check prrc with spammy user" do
      review = create(:pull_request_review, user: @turtle, pull_request: @pull)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: @turtle, pull_request_review: review, body: "free vodka")

      assert review.comment!
      refute_predicate comment, :check_for_spam?
    end

    test "don't check prrc on private repo" do
      @eric  = create(:user, login: "E",     plan: "small")
      @lloyd = create(:user, login: "lloyd", plan: "medium")
      @private_source = create(:private_repository, name: "sekret", owner: @eric, from_example: :review_comment_source)

      @private_source.add_member @lloyd
      @private_fork = create(:fork_repository, forker: @lloyd, fork_repo: @private_source, from_example: :review_comment_fork)

      @issue = create(:issue, user: @lloyd, repository: @private_source)
      @pull =
        create(:pull_request,
          repository: @private_source,
          base_repository: @private_source,
          base_user: @private_source.owner,
          base_ref: "master",
          head_repository: @private_fork,
          head_user: @private_fork.owner,
          head_ref: "topic",
          issue: @issue,
          user: @lloyd,
        )
      @issue.pull_request = @pull
      review = create(:pull_request_review, user: @lloyd, pull_request: @pull)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: @lloyd, pull_request_review: review, body: "foo")

      assert review.comment!
      refute_predicate comment, :check_for_spam?
    end

    test "don't check prrc by repo member" do
      review = create(:pull_request_review, user: @forker, pull_request: @pull)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: @forker, pull_request_review: review, body: "foo")

      assert review.comment!
      assert @pull.repository.member?(comment.user)
      refute_predicate comment, :check_for_spam?
    end
  end

  context "check for spammy PRRCs" do
    test "check that spam check happens" do
      user = @users.first
      refute_predicate user, :spammy?
      GitHub::SpamChecker.expects(:test_comment)
      perform_enqueued_jobs(only: [CheckForSpamJob, Newsies::DeliverNotificationsJob]) do
        review = create(:pull_request_review, user: user, pull_request: @pull)
        comment = create(:pull_request_review_comment, pull_request: @pull, user: user, pull_request_review: review, body: "gamble free watch online streaming tv")

        assert review.comment!
      end
    end

    test "check that spammy comment queues commenter for review" do
      user = @users.first
      refute_predicate user, :spammy?
      GlobalInstrumenter.stubs(:instrument)
      GlobalInstrumenter.expects(:instrument).with(
        "add_account_to_spamurai_queue",
        {
          account_global_relay_id: user.global_relay_id,
          additional_context: "RESQUE_CHECK_FOR_SPAM_PULL_REQUEST_REVIEW_COMMENT",
          origin: :RESQUE_CHECK_FOR_SPAM_PULL_REQUEST_REVIEW_COMMENT,
          queue_global_relay_id: SpamQueue::POSSIBLE_SPAMMER_QUEUE_GLOBAL_RELAY_ID,
        },
      )
      GitHub::SpamChecker.stubs(:test_comment).returns("totally spammy for sure")
      perform_enqueued_jobs(only: [CheckForSpamJob, Newsies::DeliverNotificationsJob]) do
        review = create(:pull_request_review, user: user, pull_request: @pull)
        comment = create(:pull_request_review_comment, pull_request: @pull, user: user, pull_request_review: review, body: "gamble free watch online streaming tv")

        assert review.comment!
      end
    end
  end

  test "does not subscribe a mentioned user if the author is spammy" do
    assert_performed_with(job: SubscribeAndNotifyJob) do
      review = create(:pull_request_review, user: @spammer, pull_request: @pull)
      comment = create(:pull_request_review_comment, pull_request: @pull, user: @spammer, pull_request_review: review, body: "Hey @#{@owner} lookit this")

      assert review.comment!

      refute @issue.subscribed?(@owner)
    end
  end
end
