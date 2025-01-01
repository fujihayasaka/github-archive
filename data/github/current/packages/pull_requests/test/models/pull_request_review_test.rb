# typed: true
# frozen_string_literal: true

require "test_helper"

class PullRequestReviewTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include GitHub::DatabaseQueryWarningsTestHelpers
  include StratocasterTestHelpers
  include GitHub::LoggerHelper
  include HydroMessageJobTestHelpers
  include HydroTestHelpers
  include DogstatsTestHelpers

  setup do
    reset_cache
    reset_monolith_redis_rate_limiter
  end

  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @forker = create(:user)
    @admin = TestEnv.test_with_all_emus? ? create(:user) : create(:staff_admin_user)
    @rando = create(:user, skip_enterprise_managed_user: true)

    @source = create(:private_repository, owner: @owner, name: "source", from_example: :review_comment_fork)
    create(:collaborator, collaborator: @forker, repository: @source, action: :write)
    create(:collaborator, collaborator: @admin, repository:  @source, action: :write)

    @fork = create(:fork_repository, forker: @forker, fork_repo: @source, from_example: :review_comment_fork)


    @org = create :organization, login: "acme", admin: @owner
    @team = create(:team, organization: @org, name: "team_dog", privacy: :closed)
    @org_repo = create(:repository, owner: @org, from_example: :pull_request_source)
    create(:collaborator, collaborator: @forker, repository: @org_repo, action: :write)
    create(:collaborator, collaborator: @admin, repository:  @org_repo, action: :write)
    create(:collaborator, collaborator: @owner, repository:  @org_repo, action: :write)
    @team.add_member @forker, adder: @owner
    @team.add_repository(@org_repo, :push)

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

    @org_pull =
      create(:pull_request,
        repository: @org_repo,
        base_repository: @org_repo,
        base_user: @org_repo.owner,
        base_ref: "master",
        head_repository: @org_repo,
        head_user: @org_repo.owner,
        head_ref: "master-merged-topic",
        issue: create(:issue, user: @admin, repository: @org_repo),
        user: @admin,
      )


    make_trusted_oauth_apps_owner
    @code_scanning_app = create(:code_scanning_integration)
    @copilot_review_app = create(:copilot_pull_request_reviewer_integration)
  end

  # Helper method to create a review with an associated comment
  #
  # Returns Array of [review, comment]
  def create_review_with_comment
    review = @pull.reviews.create!(
      user: @owner,
      head_sha: @pull.head_sha,
    )

    comment = create(:pull_request_review_comment,
      pull_request: @pull,
      user: @owner,
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 21,
      body: "ship it",
      pull_request_review_id: review.id,
    )
    [review, comment]
  end

  def callback_count_message(callback_type_name, from_count, to_count, base_message)
    "Callback count changed for #{callback_type_name} callbacks on the PullRequestReview model from #{from_count} to #{to_count}. \n#{base_message}"
  end

  context "validation" do
    test "fails validation with no head_sha" do
      review = @pull.reviews.create(user: @owner)
      refute review.valid?
      refute review.errors[:head_sha].empty?
    end

    test "fails validation with no user" do
      review = @pull.reviews.create(head_sha: "DEADBEEF" * 5)
      refute review.valid?
      refute review.errors[:user_id].empty?
    end

    test "fails validation for non-bot user for variant_type=copilot" do
      review = @pull.reviews.build(user: @owner, variant_type: :copilot)
      refute_predicate review, :valid?
      assert_includes review.errors[:user], "must be a bot for a Copilot review"
    end

    test "a nil state gets set to the initial state on validation" do
      review = @pull.reviews.create(user: @forker, head_sha: "DEADBEEF" * 5, state: nil)
      review.state = nil
      assert_predicate review, :valid?
      assert_predicate review, :pending?
    end

    test "fails validation with more than one pending review per PR per User" do
      review1 = @pull.reviews.create(head_sha: "DEADBEEF" * 5, user: @forker)
      assert review1.valid?
      assert_predicate review1, :pending?
      review2 = @pull.reviews.create(head_sha: "DEADBEEE" * 5, user: @forker)
      assert_predicate review2, :pending?
      refute review2.valid?
      assert_equal "can only have one pending review per pull request", review2.errors[:user_id].first
    end

    test "cannot request_changes on a review without a reason explaining the required changes" do
      review1 = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker)
      assert review1.valid?
      refute review1.request_changes!
      assert_predicate review1, :pending?
    end

    test "cannot submit a comment review without some sort of comments" do
      review1 = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker)
      assert review1.valid?
      refute review1.comment!
      assert_predicate review1, :pending?
    end

    # See also https://github.com/cthiel/workflow-orchestrator#guards and
    # https://github.com/cthiel/workflow-orchestrator/blob/1d11dddf123280dedf0cbefbb7da364609d2e4d6/lib/workflow.rb#L101-L111
    test "a failed request_changes! is halted with the corresponding reason" do
      review1 = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker)
      assert review1.valid?
      refute review1.request_changes!
      assert_predicate review1, :halted?
      assert_equal PullRequestReview::NEEDS_COMMENTS_WHEN_REQUESTING_CHANGES, review1.halted_because
    end

    test "passes validation for a user with multiple submitted reviews on a pull request" do
      review1 = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, body: "bod")
      review1.comment!
      assert review1.valid?
      assert_predicate review1, :commented?
      review2 = @pull.reviews.create!(head_sha: "DEADBEEE" * 5, user: @forker, body: "body")
      review2.comment!
      assert review2.valid?
      assert_predicate review2, :commented?
    end

    test "cannot create review if blocked by the repository owner" do
      blockee = create(:user)
      review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: blockee, body: "bod")
      assert_predicate review, :valid?

      @pull.repository.owner.block(blockee)
      @pull.reload

      review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: blockee, body: "bod")
      refute_predicate review, :valid?
      assert_equal "is blocked", review.errors[:user].first
    end

    test "cannot create review if blocked by PR owner and does not have write+ access" do
      blockee = create(:user)
      review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: blockee, body: "bod")
      assert_predicate review, :valid?

      @pull.user.block(blockee)
      @pull.reload

      review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: blockee, body: "bod")
      refute_predicate review, :valid?
      assert_equal "is blocked", review.errors[:user].first
    end

    test "can create review, even if blocked by PR owner, if they do have write+ access" do
      blockee = create(:user)
      create(:collaborator, collaborator: blockee, repository: @pull.repository, action: :write)

      @pull.user.block(blockee)
      @pull.reload

      review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: blockee, body: "bod")
      assert_predicate review, :valid?
    end

    context "logging for missing merge base sha" do
      test "logs when sha is missing on create" do
        assert_logged(
          "Body" => "Missing merge base sha for review",
          "db.transaction.type" => "create"
          ) do
          @pull.reviews.create(
            user: @owner,
            head_sha: @pull.head_sha,
          )
        end
      end

      test "logs when sha is missing on update" do
        review = @pull.reviews.create(
          user: @owner,
          head_sha: @pull.head_sha,
        )
        assert_logged(
          "Body" => "Missing merge base sha for review",
          "db.transaction.type" => "update"
          ) do
          review.update!(body: "blah")
        end
      end

      test "does not log when sha is present on create" do
        refute_logged(Body: "Missing merge base sha for review") do
          @pull.reviews.create(
            user: @owner,
            head_sha: @pull.head_sha,
            merge_base_sha: "DEADBEEF" * 5
          )
        end
      end

      test "does not log when sha is present on update" do
        review = @pull.reviews.create(
          user: @owner,
          head_sha: @pull.head_sha,
          merge_base_sha: "DEADBEEF" * 5
        )
        refute_logged(Body: "Missing merge base sha for review") do
          review.update!(body: "blah")
        end
      end
    end

    context "when collab-only interaction limits are enabled" do
      test "collaborator can create review" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @org.admins.first)

        review = @org_pull.reviews.new(head_sha: "DEADBEEF" * 5, user: @owner, body: "bod")
        assert_predicate review, :valid?
        assert_empty review.errors[:base]
      end

      test "non-collaborator cannot create review" do
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @org.admins.first)

        review = @org_pull.reviews.new(head_sha: "DEADBEEF" * 5, user: @rando, body: "bod")
        refute_predicate review, :valid?
        assert_includes review.errors[:base],
          "could not be created. Interactions on this repository have been restricted to collaborators only."
      end

      test "collabor can edit review" do
        review = create :pull_request_review, :approved, pull_request: @org_pull, user: @rando

        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @org.admins.first)

        assert review.update_body("hello!", @owner)
        assert_empty review.errors[:base]
      end

      test "non-collaborator cannot edit review" do
        review = create :pull_request_review, :approved, pull_request: @org_pull, user: @forker
        interaction = RepositoryInteractionAbility.new(@org_repo)
        interaction.set_ability(:collaborators_only, @org.admins.first)

        refute review.update_body("hello!", @rando)

        assert_includes review.errors[:base],
          "could not be created. Interactions on this repository have been restricted to collaborators only."
      end
    end if GitHub.interaction_limits_enabled?

    test "fails validation when updating code scanning review comments" do
      review = @pull.build_code_scanning_variant_review do |r|
        r.user = @code_scanning_app.bot
        r.body = "TEST"
      end

      review.comment!

      review.update_body("new body", @owner)
      refute_predicate review, :valid?
      assert_equal ["is not editable"], review.errors[:body]
    end
  end

  context "replies" do
    context "review in commented state" do
      test "has no comments and a body" do
        review = @pull.reviews.create!(
          user: @owner,
          head_sha: @pull.head_sha,
          state: 1,
          body: "a body",
        )
        refute_predicate review, :all_replies?
        assert_predicate review, :show_in_timeline?
      end

      test "has comments that are not replies and no body" do
        review, comment = create_review_with_comment
        reply_review = @pull.reviews.create!(
          head_sha: @pull.head_sha,
          user: @forker,
          state: 0,
        )

        2.times do
          create(:pull_request_review_comment,
            pull_request_review: reply_review,
            pull_request: @pull,
            user: @forker,
            commit_id: @pull.head_sha,
            path: "aquaman.txt",
            original_position: 21,
            body: "ship it",
          )
        end

        reply_review.trigger(:comment)
        reply_review.reload

        refute_predicate reply_review, :all_replies?
        assert_predicate reply_review, :show_in_timeline?
      end

      test "has comments that are not replies and a body" do
        review, comment = create_review_with_comment
        reply_review = @pull.pending_review_for(user: @forker, head_sha: @pull.head_sha)
        2.times do
          create(:pull_request_review_comment,
            pull_request_review: reply_review,
            pull_request: @pull,
            user: @forker,
            commit_id: @pull.head_sha,
            path: "aquaman.txt",
            original_position: 21,
            body: "ship it",
          )
        end
        reply_review.update(state: 1, body: "the body")

        refute_predicate reply_review, :all_replies?
        assert_predicate reply_review, :show_in_timeline?
      end

      test "has comments that are replies and comments that are not replies and no body" do
        review, comment = create_review_with_comment
        review.comment!

        reply_review = @pull.reviews.create!(
          head_sha: @pull.head_sha,
          user: @forker,
        )
        2.times do
          create(:pull_request_review_comment,
            pull_request_review: reply_review,
            pull_request: @pull,
            user: @forker,
            commit_id: @pull.head_sha,
            path: "aquaman.txt",
            original_position: 21,
            body: "ship it",
          )
        end

        2.times do
          create(:pull_request_review_comment,
            pull_request_review: reply_review,
            reply_to_id: comment.id,
            pull_request: @pull,
            user: @forker,
            commit_id: @pull.head_sha,
            path: "aquaman.txt",
            original_position: 21,
            body: "ship it",
          )
        end

        reply_review.trigger(:comment)
        reply_review.reload

        refute_predicate reply_review, :all_replies?
        assert_predicate reply_review, :show_in_timeline?
      end

      test "has comments that are all replies and no body" do
        review, comment = create_review_with_comment
        review.comment!

        reply_review = @pull.reviews.create!(
          head_sha: @pull.head_sha,
          user: @forker,
        )

        2.times do
          create(:pull_request_review_comment,
            pull_request_review: reply_review,
            reply_to_id: comment.id,
            pull_request: @pull,
            user: @forker,
            commit_id: @pull.head_sha,
            path: "aquaman.txt",
            original_position: 21,
            body: "ship it",
          )
        end

        reply_review.trigger(:comment)
        reply_review.reload

        assert_predicate reply_review, :all_replies?
        refute_predicate reply_review, :show_in_timeline?
      end

      test "has comments that are all replies and a body" do
        review, comment = create_review_with_comment
        review.comment!

        reply_review = @pull.reviews.create!(
          head_sha: @pull.head_sha,
          user: @forker,
          body: "this is a body",
        )
        2.times do
          create(:pull_request_review_comment,
            pull_request_review: reply_review,
            reply_to_id: comment.id,
            pull_request: @pull,
            user: @forker,
            commit_id: @pull.head_sha,
            path: "aquaman.txt",
            original_position: 21,
            body: "ship it",
          )
        end
        reply_review.comment!

        assert_predicate reply_review, :all_replies?
        assert_predicate reply_review, :show_in_timeline?
      end
    end

    context "review in approved or changes_requested state" do
      test "has no comments and no body" do
        review = @pull.reviews.create!(
          user: @owner,
          head_sha: @pull.head_sha,
          state: 40,
        )
        refute_predicate review, :all_replies?
        assert_predicate review, :show_in_timeline?
      end

      test "has no comments and a body" do
        review = @pull.reviews.create!(
          user: @owner,
          head_sha: @pull.head_sha,
          state: 40,
          body: "the body",
        )
        refute_predicate review, :all_replies?
        assert_predicate review, :show_in_timeline?
      end

      test "has comments that are all replies and no body" do
        review, comment = create_review_with_comment
        review.comment!

        reply_review = @pull.reviews.create!(
          head_sha: @pull.head_sha,
          user: @forker,
        )

        2.times do
          create(:pull_request_review_comment,
            pull_request_review: reply_review,
            reply_to_id: comment.id,
            pull_request: @pull,
            user: @forker,
            commit_id: @pull.head_sha,
            path: "aquaman.txt",
            original_position: 21,
            body: "ship it",
          )
        end

        reply_review.trigger(:request_changes)
        reply_review.reload

        assert_predicate reply_review, :all_replies?
        assert_predicate reply_review, :show_in_timeline?
      end
    end
  end

  test "permalink" do
    review = @pull.reviews.create!(
      user: @owner,
      head_sha: @pull.head_sha,
    )
    assert_equal "https://github.com/#{@source.name_with_display_owner}/pull/1#pullrequestreview-#{review.id}", review.permalink
    assert_equal "/#{@source.name_with_display_owner}/pull/1#pullrequestreview-#{review.id}", review.permalink(include_host: false)
  end

  test "submitting a review changes state" do
    review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "blah")
    assert review.pending?
    assert review.comment!
    assert review.commented?
  end

  test "creating a pending review does NOT deliver notifications" do
    review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: @owner)
    GitHub.newsies.expects(:trigger).never

    only = [AddToSearchIndexJob, SubscribeAndNotifyJob]
    perform_enqueued_jobs(only: only) do
      review.save!
    end
  end

  test "approving a review delivers notifications" do
    assert_performed_with job: SubscribeAndNotifyJob do
      review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: @owner)
      GitHub.newsies.expects(:trigger).once

      review.approve!
    end
  end

  test "submiting a code scanning review does NOT delivers notifications" do
    review = @pull.reviews.new(variant_type: :code_scanning, head_sha: "DEADBEEF" * 5, user: @code_scanning_app.bot)
    GitHub.newsies.expects(:trigger).never

    only = [AddToSearchIndexJob, SubscribeAndNotifyJob]
    perform_enqueued_jobs(only: only) do
      review.approve!
    end
  end

  test "submitting an empty copilot review does NOT deliver notifications" do
    review = @pull.reviews.new(variant_type: :copilot, head_sha: "DEADBEEF" * 5, user: @copilot_review_app.bot)
    GitHub.newsies.expects(:trigger).never

    only = [AddToSearchIndexJob, SubscribeAndNotifyJob]
    perform_enqueued_jobs(only: only) do
      review.comment!
    end
  end

  test "submiting a copilot review with comments delivers notifications" do
    review = @pull.reviews.new(variant_type: :copilot, head_sha: "DEADBEEF" * 5, user: @copilot_review_app.bot)
    create(:pull_request_review_comment,
      pull_request: @pull,
      user: @copilot_review_app.bot,
      commit_id: @pull.head_sha,
      path: "aquaman.txt",
      original_position: 21,
      body: "comment",
      pull_request_review: review,
    )

    GitHub.newsies.expects(:trigger).once

    only = [AddToSearchIndexJob, SubscribeAndNotifyJob]
    perform_enqueued_jobs(only: only) do
      review.comment!
    end
  end

  test "approving on a review notifies state changes" do
    review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: @owner, body: "blah")
    channel = GitHub::WebSocket::Channels.pull_request_review_state(@pull)

    GitHub::WebSocket.stubs(:notify_pull_request_channel).returns([])
    GitHub::WebSocket.expects(:notify_pull_request_channel)
      .with(@pull, channel, has_key(:review_id) & has_entry(state: :approved))
      .once

    review.approve!
  end

  test "submitting a review notifies with the reviewers_updated event" do
    review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: @owner, body: "blah")
    channel = GitHub::WebSocket::Channels.pull_request(@pull)

    GitHub::WebSocket.stubs(:notify_pull_request_channel).returns([])
    GitHub::WebSocket.expects(:notify_pull_request_channel)
      .with(@pull, channel, has_entry(event_updates: has_entry(ReviewRequest::LIVE_UPDATE_EVENT_NAME.to_sym => true)))
      .once

    review.comment!
  end

  context "GraphQL subscription events" do
    test "creating a pending review does not trigger a GraphQL subscription event", skip_enterprise: true do
      enable_feature_flag(:pull_request_sub_triggers)

      Platform::Schema.subscriptions.expects(:trigger).never

      create(:pull_request_review, pull_request: @pull, user: @owner)
    end

    test "approving a review triggers a pull_request_review_decision_updated GraphQL subscription event if pull_request_single_subscription is disabled", skip_enterprise: true do
      enable_feature_flag(:pull_request_sub_triggers)
      disable_feature_flag(:pull_request_single_subscription)

      review = create(:pull_request_review, pull_request: @pull, user: @owner)

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :pull_request_review_decision_updated,
        { id: @pull.global_relay_id }
      )

      review.approve!
    end

    test "approving a review triggers pull_request_info_for_list_view_updated and pull_request_review_decision_updated GraphQL subscription event if pull_request_single_subscription is enabled", skip_enterprise: true do
      enable_feature_flag(:pull_request_sub_triggers)
      enable_feature_flag(:pull_request_single_subscription)

      review = create(:pull_request_review, pull_request: @pull, user: @owner)

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :pull_request_info_for_list_view_updated,
        { id: @pull.global_relay_id },
        object: { review_decision_updated: true }
      )

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :pull_request_review_decision_updated,
        { id: @pull.global_relay_id }
      )

      review.approve!
    end

    test "requesting changes on a review triggers a pull_request_review_decision_updated GraphQL subscription event if pull_request_single_subscription is disabled", skip_enterprise: true do
      enable_feature_flag(:pull_request_sub_triggers)
      disable_feature_flag(:pull_request_single_subscription)

      review = create(:pull_request_review, pull_request: @pull, user: @owner)

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :pull_request_review_decision_updated,
        { id: @pull.global_relay_id }
      )

      review.request_changes!
    end

    test "requesting changes on a review triggers pull_request_info_for_list_view_updated and pull_request_review_decision_updated GraphQL subscription event if pull_request_single_subscription is enabled", skip_enterprise: true do
      enable_feature_flag(:pull_request_sub_triggers)
      enable_feature_flag(:pull_request_single_subscription)

      review = create(:pull_request_review, pull_request: @pull, user: @owner)

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :pull_request_info_for_list_view_updated,
        { id: @pull.global_relay_id },
        object: { review_decision_updated: true }
      )

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :pull_request_review_decision_updated,
        { id: @pull.global_relay_id }
      )

      review.request_changes!
    end

    test "submitting a comment review does not trigger a GraphQL subscription event", skip_enterprise: true do
      enable_feature_flag(:pull_request_sub_triggers)

      Platform::Schema.subscriptions.expects(:trigger).never

      review = create(:pull_request_review, pull_request: @pull, user: @owner)
      review.comment!
    end

    test "dismissing a review triggers a GraphQL pull_request_review_decision_updated subscription event if pull_request_single_subscription is disabled", skip_enterprise: true do
      enable_feature_flag(:pull_request_sub_triggers)
      disable_feature_flag(:pull_request_single_subscription)

      review = create(:pull_request_review, :submitted, :approved, pull_request: @pull, user: @owner)

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :pull_request_review_decision_updated,
        { id: @pull.global_relay_id }
      )

      review.dismiss!(@owner, message: "dismiss an approval")
    end

    test "dismissing a review triggers a GraphQL pull_request_info_for_list_view_updated and pull_request_review_decision_updated subscription event if pull_request_single_subscription is enabled", skip_enterprise: true do
      enable_feature_flag(:pull_request_sub_triggers)
      enable_feature_flag(:pull_request_single_subscription)

      review = create(:pull_request_review, :submitted, :approved, pull_request: @pull, user: @owner)

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :pull_request_info_for_list_view_updated,
        { id: @pull.global_relay_id },
        object: { review_decision_updated: true }
      )

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :pull_request_review_decision_updated,
        { id: @pull.global_relay_id }
      )

      review.dismiss!(@owner, message: "dismiss an approval")
    end

    test "updating review body does not trigger a GraphQL subscription event", skip_enterprise: true do
      enable_feature_flag(:pull_request_sub_triggers)
      Platform::Schema.subscriptions.expects(:trigger).never

      review = create(:pull_request_review, pull_request: @pull, user: @owner)
      review.update!(body: "updated body copy")
    end
  end

  context "#variant_type" do
    test "default is implicitly vanilla and can be set to code_scanning" do
      review = PullRequestReview.new
      persisted_review = review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha)
      assert_predicate review, :vanilla?
      assert_predicate persisted_review, :vanilla?

      refute_predicate review, :code_scanning?
      refute_predicate persisted_review, :code_scanning?
    end

    test "can be set to code_scanning" do
      review = PullRequestReview.new(variant_type: "code_scanning")
      persisted_review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, variant_type: "code_scanning")
      assert_predicate review, :code_scanning?
      assert_predicate persisted_review, :code_scanning?

      refute_predicate review, :vanilla?
      refute_predicate persisted_review, :vanilla?
    end
  end

  context "#variant_type" do
    test "default is implicitly vanilla and can be set to dependabot" do
      review = PullRequestReview.new
      persisted_review = review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha)
      assert_predicate review, :vanilla?
      assert_predicate persisted_review, :vanilla?

      refute_predicate review, :dependabot?
      refute_predicate persisted_review, :dependabot?
    end

    test "can be set to dependabot" do
      review = PullRequestReview.new(variant_type: "dependabot")
      persisted_review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, variant_type: "dependabot")
      assert_predicate review, :dependabot?
      assert_predicate persisted_review, :dependabot?

      refute_predicate review, :vanilla?
      refute_predicate persisted_review, :vanilla?
    end
  end

  context "can_trigger?" do
    test "returns true for valid events that can be called from the current state" do
      review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: @owner)
      assert review.can_trigger?(:approve)
    end

    test "returns false for invalid events from the current state" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "blah")
      review.approve!
      refute review.can_trigger?(:comment)
      refute review.can_trigger?(:request_changes)
      refute review.can_trigger?(:approve)
    end

    test "returns false for unknown events" do
      review = @pull.reviews.new(head_sha: "DEADBEEF" * 5, user: @owner)
      assert_raises(ArgumentError) do
        review.can_trigger?(:blah_unknown)
      end
    end
  end

  PullRequestReview::SUBMISSION_EVENTS.each do |event|
    event_method = "#{event}!"

    test "#{event} fires after_submission method" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "hi")
      review.expects(:after_submission).once
      assert review.public_send(event_method)
    end

    test "#{event} does NOT send notifications if the state persistance fails" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "hi")
      review.reload
      review.expects(:deliver_notifications).never

      only = []
      perform_enqueued_jobs(only: only) do
        review.user_id = nil
        review.public_send(event_method)
        refute review.valid?
      end
    end

    test "#{event} sets submitted_at" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "hi")
      assert_nil review.submitted_at
      assert review.public_send(event_method)
      refute_nil review.submitted_at
    end

    test "submitting a review via #{event} delivers notifications" do
      assert_performed_with job: SubscribeAndNotifyJob do
        GitHub.newsies.expects(:trigger).once
        review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "body")
        assert review.public_send(event_method)
        # call save! a couple more times to trigger after_commit and verify we don't
        # get double notifications
        review.save!
        review.body = "something else"
        review.save!
      end
    end

    test "submitting a review via #{event} marks all related comments as submitted" do
      review = @pull.reviews.create(head_sha: "DEADBEEF" * 5, user: @owner, body: "body")
      comments = []
      3.times do |n|
        comments << create(:pull_request_review_comment,
          pull_request: @pull,
          user: @owner,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 21,
          body: "comment #{n}",
          pull_request_review: review,
        )
      end
      comments.all? { |comment| assert_predicate comment, :pending? }
      assert review.public_send(event_method)
      review.review_comments.all? { |comment| assert_predicate comment, :submitted? }
    end
  end

  test "doesn't execute N+1 queries on the pull request table" do
    review = @pull.reviews.create(head_sha: "DEADBEEF" * 5, user: @owner, body: "body")
    comment_count = 3
    comment_count.times do |n|
      create(:pull_request_review_comment,
        pull_request: @pull,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 21,
        body: "comment #{n}",
        pull_request_review: review,
      )
    end

    assert_query_count_per_table({ pull_requests: 2 }) do
      assert review.comment!
    end
  end

  test "creation of approval event triggers a call to enqueue_auto_merge_job_if_enabled" do
    @pull.expects(:enqueue_auto_merge_job_if_enabled).once

    review = create(:pull_request_review, pull_request: @pull, head_sha: "DEADBEEF" * 5, user: @forker, state: PullRequestReview.state_value(:approved))
  end

  test "comment event triggers a call to enqueue_auto_merge_job_if_enabled" do
    review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "hi")

    @pull.expects(:enqueue_auto_merge_job_if_enabled).once
    assert review.public_send(:comment!)
  end

  test "changes requested event does not trigger a call to enqueue_auto_merge_job_if_enabled" do
    review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "hi")

    @pull.expects(:enqueue_auto_merge_job_if_enabled).times(0)
    assert review.public_send(:request_changes!)
  end

  test "dismissing a review triggers a call to enqueue_auto_merge_job_if_enabled" do
    review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "hi")

    @pull.expects(:enqueue_auto_merge_job_if_enabled).once
    assert review.public_send(:request_changes!)
    assert review.dismiss!(@forker, message: "dismiss an approval")
  end

  test "creating a pending review does NOT subscribe the author, mentioned users, and mentioned teams to receive notifications" do
    GitHub.newsies.expects(:subscribe_to_thread).never.returns(NewsiesHelper::RESPONSE_SUCCESS)
    GitHub.newsies.expects(:subscribe_all_to_thread).never.returns(NewsiesHelper::RESPONSE_SUCCESS)

    perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
      review = @org_pull.reviews.create!(
        head_sha: "DEADBEEF" * 5,
        user: @owner,
        body: "@#{@admin} @#{@org}/#{@team.slug} should receive notifications",
      )
    end
  end

  test "submitting review subscribes the author, mentioned users, and mentioned teams to receive notifications" do
    review = @org_pull.reviews.create(
      head_sha: "DEADBEEF" * 5,
      user: @owner,
      body: "@#{@admin} @#{@org}/#{@team.slug} should receive notifications",
    )

    # Subscribes the author
    GitHub.newsies.expects(:subscribe_to_thread).once.with(
      @owner,
      review.repository,
      review.pull_request.issue,
      :comment,
      [],
    ).returns(NewsiesHelper::RESPONSE_SUCCESS)

    # Subscribes the mentioned user
    GitHub.newsies.expects(:subscribe_to_thread).once.with(
      @admin,
      review.repository,
      review.pull_request.issue,
      :mention,
      [],
    ).returns(NewsiesHelper::RESPONSE_SUCCESS)

    # Subscribes the users of a mentioned team
    GitHub.newsies.expects(:subscribe_all_to_thread).once.with(
      [@forker],
      review.repository,
      review.pull_request.issue,
      "team-mentioned",
    ).returns(NewsiesHelper::RESPONSE_SUCCESS)

    perform_enqueued_jobs(only: [SubscribeAndNotifyJob]) do
      review.approve!
    end
  end

  context "mentioned_users" do
    test "returns mentioned users including users mentioned in comments" do
      user = create(:user)
      @pull.repository.add_member user, action: :write

      review = @pull.reviews.create!(head_sha: @pull.head_sha, user: @owner, body: "hi @#{user}")

      mentioned_users = [user]
      2.times do
        mentioned_user = create(:user)
        @pull.repository.add_member mentioned_user, action: :write
        mentioned_users << mentioned_user

        create(:pull_request_review_comment,
          pull_request: @pull,
          user: @owner,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 21,
          body: "@#{mentioned_user}",
          pull_request_review_id: review.id,
        )
      end

      assert_same_elements mentioned_users, review.mentioned_users
    end
  end

  context "mentioned_usernames" do
    test "returns mentioned user names including names of users mentioned in comments" do
      user = create(:user)
      @pull.repository.add_member user, action: :write

      review = @pull.reviews.create!(head_sha: @pull.head_sha, user: @owner, body: "hi @#{user}")

      mentioned_users = [user]
      2.times do
        mentioned_user = create(:user)
        @pull.repository.add_member mentioned_user, action: :write
        mentioned_users << mentioned_user

        create(:pull_request_review_comment,
          pull_request: @pull,
          user: @owner,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 21,
          body: "@#{mentioned_user}",
          pull_request_review_id: review.id,
        )
      end

      assert_same_elements mentioned_users.map(&:login), review.mentioned_usernames
    end
  end

  context "mentioned_teams" do
    test "returns mentioned teams including teams mentioned in comments" do
      team = create(:team, organization: @org, privacy: :closed)
      team.add_repository(@org_pull.repository, :push)

      review = @org_pull.reviews.create!(head_sha: @org_pull.head_sha, user: @owner, body: "hi @#{team.combined_slug}")

      mentioned_teams = [team]
      2.times do
        mentioned_team = create(:team, organization: @org, privacy: :closed)
        mentioned_team.add_repository(@org_pull.repository, :push)
        mentioned_teams << mentioned_team

        create(:pull_request_review_comment,
          pull_request: @org_pull,
          user: @owner,
          commit_id: @org_pull.head_sha,
          path: "file11",
          original_position: 1,
          body: "@#{mentioned_team.combined_slug}",
          pull_request_review_id: review.id,
        )
      end

      assert_same_elements mentioned_teams, review.mentioned_teams
    end
  end

  test "approving a review to a closed pull request does change state" do
    @pull.close
    review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "small dogs > big dogs")

    assert_predicate review, :pending?
    assert review.approve!
    assert review.valid?
    assert_predicate review, :approved?

    assert_includes review.body,  "small dogs > big dogs"
    refute review.halted_because, "Can only request changes for open pull requests"
  end

  test "request_changes! a review to a closed pull request does change state" do
    @pull.close
    review = @pull.reviews.create(head_sha: "DEADBEEF" * 5, user: @owner, body: "coyotes > big dogs")
    assert_predicate review, :pending?

    assert review.request_changes!
    assert_predicate review, :changes_requested?

    refute review.halted_because, "Can only request changes for open pull requests"
  end

  context "#async_review_threads_for" do
    test "returns all review threads in the review for given viewer" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
      )
      create(:pull_request_review_comment,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 21,
        body: "ship it",
        pull_request: @pull,
        pull_request_review: review,
      )
      create(:pull_request_review_comment,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
        body: "another comment",
        pull_request: @pull,
        pull_request_review: review,
      )
      review.comment!
      review.reload

      threads = review.async_review_threads_for(@owner).sync
      assert_equal 2, threads.size
      threads.sort_by!(&:id)

      first_comment = threads[0].review_comments.first
      assert_equal "aquaman.txt", first_comment.path
      assert_equal 21, first_comment.original_position

      first_comment = threads[1].review_comments.first
      assert_equal "aquaman.txt", first_comment.path
      assert_equal 19, first_comment.original_position
    end

    test "returns file level review threads" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
      )
      create(:pull_request_review_comment,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 21,
        body: "ship it",
        pull_request: @pull,
        pull_request_review: review,
      )
      comment_for_file_thread = create(:pull_request_review_comment,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
        body: "another comment",
        pull_request: @pull,
        pull_request_review: review,
      )

      comment_for_file_thread.pull_request_review_thread.update!(original_position: nil, subject_type: :file)

      review.comment!
      review.reload

      threads = review.async_review_threads_for(@owner).sync
      threads.sort_by!(&:id)

      assert_equal 2, threads.size

      assert_equal "line", threads.first.subject_type
      assert_equal "file", threads.last.subject_type
    end
  end

  context "#async_review_comments_for" do
    test "returns all review comments in the review visible for the given viewer" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
      )

      first_comment = create(:pull_request_review_comment,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 21,
        body: "ship it",
        pull_request: @pull,
        pull_request_review: review,
      )

      second_comment = create(:pull_request_review_comment,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 19,
        body: "another comment",
        pull_request: @pull,
        pull_request_review: review,
      )
      review.comment!
      review.reload

      review_comments = review.async_review_comments_for(@owner).sync
      assert_equal 2, review_comments.size
      assert_same_elements [first_comment, second_comment], review_comments
    end

    if GitHub.spamminess_check_enabled?
      test "does not return spammy review comments in the review for regular viewers", spammy_only: true do
        spammer = create(:user, spammy: true)

        review = @pull.reviews.create!(
          user: spammer,
          head_sha: @pull.head_sha,
        )

        first_comment = create(:pull_request_review_comment,
          user: spammer,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 21,
          body: "ship it",
          pull_request: @pull,
          pull_request_review: review,
        )

        second_comment = create(:pull_request_review_comment,
          user: spammer,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 19,
          body: "another comment",
          pull_request: @pull,
          pull_request_review: review,
        )
        review.comment!
        review.reload

        review_comments = review.async_review_comments_for(@owner).sync
        assert_equal 0, review_comments.size

        review_comments = review.async_review_comments_for(spammer).sync
        assert_same_elements [first_comment, second_comment], review_comments
      end
    else
      test "does return spammy review comments in the review for regular viewers" do
        spammer = create(:user, spammy: true)

        review = @pull.reviews.create!(
          user: spammer,
          head_sha: @pull.head_sha,
        )

        first_comment = create(:pull_request_review_comment,
          user: spammer,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 21,
          body: "ship it",
          pull_request: @pull,
          pull_request_review: review,
        )

        second_comment = create(:pull_request_review_comment,
          user: spammer,
          commit_id: @pull.head_sha,
          path: "aquaman.txt",
          original_position: 19,
          body: "another comment",
          pull_request: @pull,
          pull_request_review: review,
        )
        review.comment!
        review.reload

        review_comments = review.async_review_comments_for(@owner).sync
        assert_equal [first_comment, second_comment], review_comments

        review_comments = review.async_review_comments_for(spammer).sync
        assert_equal [first_comment, second_comment], review_comments
      end
    end
  end

  context "instrumentation" do
    test "deletion is recorded in audit log" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "great job!")
      events = assert_performed_audit_entries(count: 1, only: "pull_request_review.delete") do
        review.destroy
      end
      assert_subset_hash({ pull_request_id: @pull.id, review_id: review.id }, events.first)
    end

    test "deletion works without a user" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "great job!")
      review.user = nil

      events = assert_performed_audit_entries(count: 1, only: "pull_request_review.delete") do
        review.destroy
      end
      assert_subset_hash({ pull_request_id: @pull.id, review_id: review.id, spammy: nil, allowed: nil }, events.first)
    end

    test "submission is recorded in audit log" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "great job!")
      events = assert_performed_audit_entries(count: 1, only: "pull_request_review.submit") do
        review.approve!
      end

      expected = {
        actor: @owner.login,
        actor_id: @owner.id,
        pull_request_id: @pull.id,
        review_id: review.id,
      }
      assert_subset_hash(expected, events.first)
    end

    test "dismissal is recorded in audit log" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "great job!", state: :approved)
      events = assert_performed_audit_entries(count: 1, only: "pull_request_review.dismiss") do
        review.dismiss!(@admin, message: "No longer relevant")
      end

      expected = {
        actor: @admin.login,
        actor_id: @admin.id,
        pull_request_id: @pull.id,
        review_id: review.id,
      }
      assert_subset_hash(expected, events.first)
    end

    test "submission is instrumented" do
      events = subscribe "pull_request_review.submit"
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "great job!",
      )
      expected_payload = {
        spammy: false,
        pull_request_id: @pull.id,
        pull_request_author: @pull.user.login,
        pull_request_author_id: @pull.user_id,
        pull_request_url: @pull.permalink,
        pull_request_title: @pull.title,
        repo: @pull.repository.nwo,
        repo_id: @pull.repository.id,
        public_repo: @pull.repository.public?,
        issue_id: @pull.issue.id,
        review_id: review.id,
        new_reviewer_was_added: true,
        body: "great job!",
        id: review.id,
        actor: @owner.login,
        actor_id: @owner.id,
        state: PullRequestReview.state_value(:commented),
        allowed: true,
      }

      review.comment!
      review.save!
      assert event = events.pop, "expected a submit event to be triggered"
      assert_subset_hash expected_payload, event.payload
    end

    test "instruments the 'new_reviewer_was_added' key" do
      events = subscribe "pull_request_review.submit"

      _, queries = log_queries do
        review = @pull.reviews.create!(
          user: @owner,
          head_sha: @pull.head_sha,
          body: "great job!",
        )
        review.comment!
        review.save!
      end

      refute_nil queries.find { |q| q.sql.match?(/SELECT DISTINCT.*pull_request_reviews/) }
      assert event = events.pop, "expected a submit event to be triggered"
      assert_equal true, event.payload[:new_reviewer_was_added]
    end

    test "submission calls stratocaster" do
      T.unsafe(GitHub).reset_stratocaster

      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "great job!",
      )

      perform_enqueued_jobs(only: [ProcessEventJob]) do
        review.comment!
      end

      events = GitHub.stratocaster_store.all

      event = events.first
      assert_equal 1, events.size
      assert_equal "PullRequestReviewEvent", event.event_type
    end
  end

  context "destroy_pending_comments" do
    test "destroys pending comments" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
      )

      other_comment = create(:pull_request_review_comment, pull_request: @pull)
      comment = create(:pull_request_review_comment,
        pull_request: @pull,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 21,
        body: "ship it",
        pull_request_review_id: review.id,
      )

      review.destroy_pending_comments

      assert_nil PullRequestReviewComment.find_by(id: comment)
      assert PullRequestReviewComment.find_by(id: other_comment)
    end
  end

  context "destroy_if_empty" do
    test "destroys a review if it has no comments or body and is a comment review" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "This will be deleted",
        state: :commented,
      )
      review.body = nil
      review.destroy_if_empty

      assert_nil PullRequestReview.find_by(id: review.id)
    end

    test "does not destroy a review if it has a body and is a comment review" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "This will be deleted",
        state: :commented,
      )
      review.destroy_if_empty
      refute_nil PullRequestReview.find_by(id: review.id)
    end

    test "does not destroy a review if it has a comment and is a comment review" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
      )

      comment = create(:pull_request_review_comment,
        pull_request: @pull,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 21,
        body: "ship it",
        pull_request_review_id: review.id,
      )

      review.comment!
      review.destroy_if_empty
      refute_nil PullRequestReview.find_by(id: review.id)
    end

    test "does not destroy a review if it has no body or comments but is approved" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        state: :approved,
      )

      review.destroy_if_empty

      refute_nil PullRequestReview.find_by(id: review.id)
    end

    test "destroys a review if it has no body or comments and has requested changes" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "This wil be deleted",
        state: :changes_requested,
      )

      review.body = nil
      review.destroy_if_empty

      assert_nil PullRequestReview.find_by(id: review.id)
    end

    test "does not destroy a review if it has a body and changes are requested" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "This will be deleted",
        state: :changes_requested,
      )
      review.destroy_if_empty
      refute_nil PullRequestReview.find_by(id: review.id)
    end

    test "does not destroy a review if it has a comment and changes are requested" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
      )

      comment = create(:pull_request_review_comment,
        pull_request: @pull,
        user: @owner,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 21,
        body: "ship it",
        pull_request_review_id: review.id,
      )

      review.request_changes!
      review.destroy_if_empty
      refute_nil PullRequestReview.find_by(id: review.id)
    end
  end

  context "#destroy" do
    test "destroys associated pull_request_reviews_review_requests" do
      request = @pull.request_review_from(reviewers: [@owner], actor: @owner)

      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
        body: "approved!",
      )

      assert_difference "PullRequestReviewsReviewRequest.count", 1 do
        review.approve!
      end

      assert_difference "PullRequestReviewsReviewRequest.count", -1 do
        perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
          review.destroy
        end
      end
    end

    test "destroys only empty review comments and review threads" do
      review = @pull.reviews.create!(
        user: @owner,
        head_sha: @pull.head_sha,
      )

      comment1 = create(:pull_request_review_comment,
        pull_request: @pull,
        user: @owner,
        pull_request_review: review,
      )
      shared_review_thread = comment1.pull_request_review_thread

      comment2 = create(:pull_request_review_comment,
        pull_request: @pull,
        user: @owner,
        pull_request_review: review,
      )
      review_thread2 = comment2.pull_request_review_thread
      assert review.comment!

      forker_review = @pull.reviews.create!(
        user: @forker,
        head_sha: @pull.head_sha,
      )
      reply_comment = create(:pull_request_review_comment,
        pull_request: @pull,
        user: @forker,
        pull_request_review: forker_review,
        reply_to_id: comment1.id,
        pull_request_review_thread: shared_review_thread
      )
      assert forker_review.comment!

      perform_enqueued_jobs(only: DestroyDependentRecordsJob) { review.destroy }

      [review, comment1, comment2, review_thread2].each_with_index do |record, i|
        assert_raises(ActiveRecord::RecordNotFound, "index is: #{i}\n#{record.inspect}") { record.reload }
      end

      assert shared_review_thread.reload, "should not have been deleted"
      assert reply_comment.reload, "should not have been deleted"
      assert forker_review.reload, "should not have been deleted"
    end
  end

  test "submitted scope excludes pending reviews" do
    pending_review   = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "pending",   state: :pending)
    commented_review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "commented", state: :commented)
    approved_review  = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "approved",  state: :approved)
    empty_approval   = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, state: :approved)
    changes_requested_review  = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "changes_requested",  state: :changes_requested)

    submitted_reviews = @pull.reviews.submitted

    refute_includes submitted_reviews, pending_review,   "Pending review should not be considered submitted"
    assert_includes submitted_reviews, commented_review, "Commented review should be considered submitted"
    assert_includes submitted_reviews, approved_review,  "Approved review should be considered submitted"
    assert_includes submitted_reviews, empty_approval,  "Empty approved review should be considered submitted"
    assert_includes submitted_reviews, changes_requested_review,  "changes_requested review should be considered submitted"
  end

  context ".visible_in_timeline_for" do
    test "returns only non-commented reviews without body and all replies" do
      review = @pull.reviews.create!(user: create(:user), head_sha: @pull.head_sha)
      thread = @pull.review_threads.build(pull_request_review: review) # autosaved by comment
      thread.build_first_comment(
        body: "ship it",
        path: "aquaman.txt",
        line: 21,
      ).save!
      review.comment!

      reply_review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha)
      thread.build_reply(
        pull_request_review: reply_review,
        user: @owner,
        body: "nice",
      ).save!
      reply_review.approve!

      assert_includes @pull.reviews.visible_in_timeline_for(@rando), reply_review
    end

    test "returns only commented reviews with body and all replies" do
      review = @pull.reviews.create!(user: create(:user), head_sha: @pull.head_sha)
      thread = @pull.review_threads.build(pull_request_review: review) # autosaved by comment
      thread.build_first_comment(
        body: "ship it",
        path: "aquaman.txt",
        line: 21,
      ).save!
      review.comment!

      reply_review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "foobar")
      thread.build_reply(
        pull_request_review: reply_review,
        user: @owner,
        body: "nice",
      ).save!
      reply_review.comment!

      assert_includes @pull.reviews.visible_in_timeline_for(@rando), reply_review
    end

    test "returns only commented reviews without body and not all replies" do
      review = create(:pull_request_review, pull_request: @pull, head_sha: "DEADBEEF" * 5, user: @rando)
      create(:pull_request_review_comment,
        pull_request: @pull,
        user: @rando,
        commit_id: @pull.head_sha,
        path: "aquaman.txt",
        original_position: 21,
        body: "ship it",
        pull_request_review_id: review.id,
      )
      review.comment!

      assert_includes @pull.reviews.visible_in_timeline_for(@rando), review
    end

    test "returns no pending reviews from other users" do
      review = create(:pull_request_review, pull_request: @pull, head_sha: "DEADBEEF" * 5, user: @owner, body: "foobar")
      refute_includes @pull.reviews.visible_in_timeline_for(@rando), review
    end

    test "returns no reviews from spammy users" do
      review = create(:pull_request_review, pull_request: @pull,
        head_sha: "DEADBEEF" * 5,
        user: create(:user, spammy: true),
        body: "foobar"
      )
      refute_includes @pull.reviews.visible_in_timeline_for(@rando), review
    end
  end

  context ".for_organization" do
    test "works ok for organizations with no repositories" do
      org = create(:organization)
      assert_predicate PullRequestReview.for_organization(org), :empty?
    end

    test "returns records for orgs with PR reviews" do
      @org_pull.reviews.create!(user: @admin, head_sha: @org_pull.head_sha)
      assert_equal 1, PullRequestReview.for_organization(@org).count
    end
  end

  context ".for_viewer" do
    test "does not see pending reviews from other users" do
      review1 = create(:pull_request_review, pull_request: @pull, head_sha: "DEADBEEF" * 5, user: @rando)
      assert_equal [], @pull.reviews.for_viewer(@owner)
    end

    test "sees user's own pending reviews" do
      review1 = create(:pull_request_review, pull_request: @pull, head_sha: "DEADBEEF" * 5, user: @owner)
      assert_equal [review1], @pull.reviews.for_viewer(@owner)
    end

    test "includes reply reviews" do
      head_sha = @pull.head_sha
      review = create(:pull_request_review, pull_request: @pull, head_sha: head_sha, user: @rando)
      comment1 = create(:pull_request_review_comment,
        pull_request: @pull,
        user: @rando,
        commit_id: head_sha,
        path: "aquaman.txt",
        position: 1,
        pull_request_review_id: review.id,
      )
      review.comment!

      reply_review = create(:pull_request_review, pull_request: @pull, head_sha: head_sha, user: @owner)
      reply_comment = create(:pull_request_review_comment,
        pull_request: @pull,
        user: @owner,
        commit_id: head_sha,
        path: "aquaman.txt",
        position: 1,
        reply_to_id: comment1.id,
        pull_request_review_thread: comment1.pull_request_review_thread,
        pull_request_review: reply_review,
      )
      reply_review.comment!
      assert_predicate reply_review, :all_replies?

      assert_same_elements [review, reply_review], @pull.reviews.for_viewer(@rando)
    end
  end

  test "only allows writers to comment when locked" do
    issue  = @pull.issue
    repo   = issue.repository
    owner  = TestEnv.test_with_all_emus? ? repo.owner.admin : repo.owner
    collab = create(:user)
    user   = create(:user)
    staff  = TestEnv.test_with_all_emus? ? create(:user) : create(:staff_admin_user)

    create(:collaborator, collaborator: staff, repository: repo, action: :write)

    issue.lock(staff)
    assert issue.locked?

    create(:collaborator, collaborator: collab, repository: repo)

    review = @pull.reviews.create(user: collab, head_sha: @pull.head_sha, state: :approved)
    assert review.valid?, review.errors.full_messages.join("\n")

    review = @pull.reviews.create(user: owner, head_sha: @pull.head_sha, state: :approved)
    assert review.valid?, review.errors.full_messages.join("\n")

    review = @pull.reviews.create(user: user, head_sha: @pull.head_sha, state: :approved)
    assert !review.valid?, review.errors.full_messages.join("\n")
  end

  test "doesn't error when deleting the attached notifications" do
    review, comment = create_review_with_comment
    review.update(pull_request_id: nil)
    review.destroy_notification_summary
  end

  test "notifications_thread is the issue" do
    review, _ = create_review_with_comment
    assert_equal @pull.issue, review.notifications_thread
  end

  test "clears contribution cache on creation" do
    Contribution.expects(:clear_caches_for_user).with(@owner, context: "create_pull_request_review")

    @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "great job!")
  end

  test "has a safe user" do
    review = create(:pull_request_review, :approved, pull_request: @pull, user: @forker)

    assert_equal @forker, review.safe_user

    @forker.delete
    review.reload

    assert_equal User.ghost, review.safe_user
  end

  test "forbids author from approving" do
    review = create(:pull_request_review, pull_request: @pull, user: @forker)
    refute review.approve!
    assert_equal "Can not approve your own pull request", review.halted_because
  end

  test "cannot leave an approving review on an old head sha if stale reviews are dismissed" do
    create(:protected_branch,
      repository: @pull.repository,
      creator: @owner,
      name: "master",
      pull_request_reviews_enforcement_level: :non_admins,
      dismiss_stale_reviews_on_push: true
    )

    # Find a sha that doesn't match the current PR head_sha
    head = @pull.comparison.commits.detect { |commit| commit.oid == @pull.head_sha }
    old_head = head.parent_oids[0]
    refute_equal old_head, @pull.head_sha, "Should have retrieved an OID that doesn't match the PRs head_sha"

    review = @pull.reviews.create!(
      user: @owner,
      head_sha: old_head,
    )
    create(:pull_request_review_comment,
      pull_request: @pull,
      user: @owner,
      commit_id: old_head,
      path: "aquaman.txt",
      original_position: 21,
      body: "ship it",
      pull_request_review_id: review.id,
    )

    refute review.approve!, "Should not be able to approve PR"
    assert_equal "This pull request has been updated since you started reviewing. Please review the latest changes and resubmit.", review.halted_because
    assert review.halted?
  end

  test "forbids post-open pushers from approving when option enabled on protected branch" do
    enable_feature_flag(:disqualify_pr_pushers_from_approving, @pull.repository)

    @protected_branch = create(:protected_branch,
      repository: @pull.repository,
      creator: @owner,
      pull_request_reviews_enforcement_level: :non_admins,
      ignore_approvals_from_contributors: true
    )
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      perform_enqueued_jobs(only: [PullRequestSynchronizationJob, SynchronizePullRequestJob]) do
        @fork.refs.find(@pull.head_ref).append_commit({ message: "a", committer: @owner }, @owner)
      end
    end
    review = create(:pull_request_review, pull_request: @pull, user: @owner)
    refute review.approve!
    assert_equal "Can not approve a pull request you pushed to after it was opened", review.halted_because
  end

  test "forbids approval of last pusher when both ignore approvals and last pusher options are enabled" do
    enable_feature_flag(:disqualify_pr_pushers_from_approving, @pull.repository)

    @protected_branch = create(:protected_branch,
      repository: @pull.repository,
      creator: @owner,
      pull_request_reviews_enforcement_level: :non_admins,
      ignore_approvals_from_contributors: true,
      required_approving_review_count: 1,
      require_last_push_approval: true
    )

    other_user = create(:user)
    @source.add_member other_user, action: :write
    perform_enqueued_hydro_jobs(only: [HydroRepositoriesOnPushJob]) do
      perform_enqueued_jobs(only: [PullRequestSynchronizationJob, SynchronizePullRequestJob]) do
        @fork.refs.find(@pull.head_ref).append_commit({ message: "a", committer: @owner }, @owner)
        @fork.refs.find(@pull.head_ref).append_commit({ message: "a", committer: other_user }, other_user)
      end
    end

    other_user_review = create(:pull_request_review, pull_request: @pull, user: other_user)
    refute other_user_review.approve!
    assert_equal "Can not approve a pull request you pushed to after it was opened", other_user_review.halted_because
  end

  if GitHub.code_review_limits_enabled?
    test "forbids drive-by users from approving when feature and option enabled" do
      @pull.repository.restrict_non_comment_pull_request_reviews(actor: @owner)

      review = create(:pull_request_review, pull_request: @pull, user: @rando)
      refute review.approve!
      assert_equal "Can not approve a pull request without explicit repository access", review.halted_because
    end if GitHub.code_review_limits_enabled?

    test "forbids drive-by users from requesting changes when feature and option enabled" do
      @pull.repository.restrict_non_comment_pull_request_reviews(actor: @owner)

      review = create(:pull_request_review, pull_request: @pull, user: @rando)
      refute review.request_changes!
      assert_equal "Can not request changes on a pull request without explicit repository access", review.halted_because
    end if GitHub.code_review_limits_enabled?

    test "permits authorized users to approve when feature and option enabled" do
      @pull.repository.restrict_non_comment_pull_request_reviews(actor: @owner)

      review = create(:pull_request_review, pull_request: @pull, user: @owner)
      assert review.approve!
      assert_equal :approved, PullRequestReview.state_name(review.state)
    end if GitHub.code_review_limits_enabled?

    test "permits authorized users to request changes when feature flag and option enabled" do
      @pull.repository.restrict_non_comment_pull_request_reviews(actor: @owner)

      review = create(:pull_request_review, pull_request: @pull, user: @owner)
      assert review.request_changes!
      assert_equal :changes_requested, PullRequestReview.state_name(review.state)
    end if GitHub.code_review_limits_enabled?

    test "permits drive-by users to approve when feature is enabled but option is disabled" do
      @pull.repository.unrestrict_non_comment_pull_request_reviews(actor: @owner)
      review = create(:pull_request_review, pull_request: @pull, user: @rando)

      assert review.approve!
      assert_equal :approved, PullRequestReview.state_name(review.state)
    end if GitHub.code_review_limits_enabled?

    test "permits drive-by users to request changes when feature is enabled but option is disabled" do
      @pull.repository.unrestrict_non_comment_pull_request_reviews(actor: @owner)
      review = create(:pull_request_review, pull_request: @pull, user: @rando)

      assert review.request_changes!
      assert_equal :changes_requested, PullRequestReview.state_name(review.state)
    end if GitHub.code_review_limits_enabled?
  end

  test "permits drive-by users to approve when option is enabled but feature is disabled" do
    disable_feature_flag(:code_review_limits)
    @pull.repository.restrict_non_comment_pull_request_reviews(actor: @owner)
    review = create(:pull_request_review, pull_request: @pull, user: @rando)

    assert review.approve!
    assert_equal :approved, PullRequestReview.state_name(review.state)
  end unless GitHub.code_review_limits_enabled?

  test "permits drive-by users to request changes when option is enabled but feature is disabled" do
    @pull.repository.restrict_non_comment_pull_request_reviews(actor: @owner)
    review = create(:pull_request_review, pull_request: @pull, user: @rando)

    assert review.request_changes!
    assert_equal :changes_requested, PullRequestReview.state_name(review.state)
  end unless GitHub.code_review_limits_enabled?

  test "allows post-open pushers to approve when option disabled on protected branch" do
    @protected_branch = create(:protected_branch,
      repository: @pull.repository,
      creator: @owner,
      pull_request_reviews_enforcement_level: :non_admins,
      ignore_approvals_from_contributors: false
    )

    @fork.refs.find(@pull.head_ref).append_commit({ message: "a", committer: @owner }, @owner)
    review = create(:pull_request_review, pull_request: @pull, user: @owner)
    assert review.approve!
    assert_equal :approved, PullRequestReview.state_name(review.state)
  end

  context "dismissing reviews" do
    test "dismissing a review to a closed pull request does not change state" do
      @pull.close
      review = create(:pull_request_review, pull_request: @pull, head_sha: "DEADBEEF" * 5, user: @forker, state: PullRequestReview.state_value(:changes_requested))
      assert_predicate review, :changes_requested?
      refute review.dismiss!(@forker, message: "the message")
      assert_predicate review, :changes_requested?
      assert_equal "Can only dismiss reviews on open pull requests", review.halted_because
    end

    test "dismissing a review to a closed pull request does not create dismiss event" do
      @pull.close
      review = create(:pull_request_review, pull_request: @pull, head_sha: "DEADBEEF" * 5, user: @forker, state: PullRequestReview.state_value(:changes_requested))

      events = subscribe "pull_request_review.dismiss"
      refute review.dismiss!(@forker, message: "the message")

      assert_equal events.size, 0
    end

    test "can not be dismissed by a random person" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, state: PullRequestReview.state_value(:approved))
      assert_predicate review, :approved?

      refute review.can_be_dismissed_by?(@rando)
    end

    test "can be dismissed by collaborators" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved))
      assert_predicate review, :approved?

      assert review.can_be_dismissed_by?(@forker)
      assert review.can_be_dismissed_by?(@admin)
      assert review.can_be_dismissed_by?(@owner)
    end

    test "requires a message to be dismissed" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved))
      assert_predicate review, :approved?

      refute review.dismiss!(@forker, message: " ")
      assert_predicate review, :approved?
    end

    test "records the dismissal message on the issue event" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved))
      assert_predicate review, :approved?

      assert review.dismiss!(@forker, message: "YOLO")
      assert event = @pull.issue.events.last

      assert_equal "YOLO", event.message
    end

    test "exposes prior review state via the dismissed_review_state method" do
      approved_review = @pull.reviews.create!(
        head_sha: "DEADBEEF" * 5,
        user: @owner,
        state: PullRequestReview.state_value(:approved)
      )
      assert_nil approved_review.dismissed_review_state
      approved_review.dismiss!(@forker, message: "Nah!")
      approved_review.reload
      assert_equal PullRequestReview.state_value(:approved), approved_review.dismissed_review_state

      change_request = create(:pull_request_review, pull_request: @pull, user: @owner)
      change_request.request_changes!
      assert_nil change_request.dismissed_review_state
      change_request.dismiss!(@forker, message: "Wat?")
      change_request.reload
      assert_equal PullRequestReview.state_value(:changes_requested), change_request.dismissed_review_state

      # As a batch method, multiple review's states can be checked at once.

      just_a_comment = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "blah")
      just_a_comment.comment!
      another_dismissed_approval = @pull.reviews.create!(
        head_sha: "DEADBEEF" * 5,
        user: @owner,
        state: PullRequestReview.state_value(:approved)
      )
      another_dismissed_approval.dismiss!(@forker, message: "Again, no")
      another_change_request = create(:pull_request_review, pull_request: @pull, user: @owner)
      another_change_request.request_changes!

      reviews = PullRequestReview.last(5)

      GitHub::PrefillAssociations.prefill_batch_method(reviews, :dismissed_review_state)

      states = T.let(nil, T.untyped)

      assert_no_queries do
        states = reviews.map(&:dismissed_review_state)
      end

      assert_equal [
        PullRequestReview.state_value(:approved),
        PullRequestReview.state_value(:changes_requested),
        nil,
        PullRequestReview.state_value(:approved),
        nil,
      ], states
    end

    test "allows dismissing via commit OID without a message" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved))
      assert_predicate review, :approved?

      assert review.dismiss!(@forker, message: nil, via_commit_oid: "f5c81cbed047287fff802a77213038d030b80ddd")
      assert_predicate review, :dismissed?
    end

    test "records the dismissal commit OID on the issue event" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved))
      assert_predicate review, :approved?

      assert review.dismiss!(@forker, via_commit_oid: "f5c81cbed047287fff802a77213038d030b80ddd")
      assert event = @pull.issue.events.last

      assert_equal "f5c81cbed047287fff802a77213038d030b80ddd", event.after_commit_oid
    end

    test "doesn't generate a dismiss event when no message is provided" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved))
      assert_predicate review, :approved?

      events = subscribe "pull_request_review.dismiss"
      refute review.dismiss!(@forker, message: " ")

      assert_equal events.size, 0
    end

    test "moves review to dismissed state" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved))
      assert_predicate review, :approved?

      assert review.dismiss!(@forker, message: "dismiss an approval")
      assert_valid review
      assert_predicate review.reload, :dismissed?
    end

    test "dismissing review triggers dismiss webhook" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved))
      assert_predicate review, :approved?

      events = subscribe "pull_request_review.dismiss"

      assert review.dismiss!(@forker, message: "dismiss an approval")
      assert_valid review

      expected_payload = {
        review_id:       review.id,
        spammy:          review.user.spammy?,
        pull_request_id: review.pull_request.id,
        pull_request_url: review.pull_request.permalink,
        pull_request_title: review.pull_request.title,
        repo:            @pull.repository.nwo,
        repo_id:         @pull.repository.id,
        public_repo:     @pull.repository.public?,
        body:            nil,
        allowed:         true,
        issue_id:        review.pull_request.issue.id,
        actor:           @forker.login,
        actor_id:        @forker.id,
      }

      assert event = events.pop, "expected an dismiss event to be triggered"
      assert_subset_hash expected_payload, event.payload

      assert_predicate review.reload, :dismissed?
    end
  end

  context "editing a review" do
    test "instruments a pull_request_review.update event" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, body: "Old Body", user: @owner, state: PullRequestReview.state_value(:approved))

      events = subscribe "pull_request_review.update"
      review.update_body("New Body", @owner)

      expected_payload = {
        review_id: review.id,
        spammy: review.user.spammy?,
        pull_request_id: review.pull_request.id,
        pull_request_url: review.pull_request.permalink,
        pull_request_title: review.pull_request.title,
        repo: @pull.repository.nwo,
        repo_id: @pull.repository.id,
        public_repo: @pull.repository.public?,
        body: "New Body",
        changes: { old_body: "Old Body", body: "New Body" },
        allowed: true,
      }

      assert event = events.pop, "expected an update event to be triggered"
      assert_subset_hash expected_payload, event.payload
    end

    test "editable_by? with anonymous user and ghost author" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved))

      review.user.destroy
      review.reload

      refute review.editable_by?(nil)
    end

    test "uses the editing user (not the original user) permissions when editing", skip_with_all_emus: true do
      repo  = @pull.repository
      owner = repo.owner
      owner.update(plan: "medium")

      user = create(:user, plan: "medium")
      user_private_repo   = create(:private_repository, owner: user)
      owner_private_repo  = create(:private_repository, owner: owner)
      user_private_issue  = create(:issue, repository: user_private_repo,  user: user)
      owner_private_issue = create(:issue, repository: owner_private_repo, user: owner)

      user_private_reference  = [user_private_repo.name_with_display_owner,  user_private_issue.number].join("#")
      owner_private_reference = [owner_private_repo.name_with_display_owner, owner_private_issue.number].join("#")

      body  = "Hooray! a comment with some references: "
      body += user_private_reference + " "
      body += owner_private_reference

      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved), body: body)

      assert_includes review.body, "Hooray!"
      refute_includes review.body_html, %Q[href="#{user_private_issue.permalink}"]
      assert_includes review.body_html, %Q[href="#{owner_private_issue.permalink}"]

      body  = "Hooray! editing the comment with some references: "
      body += user_private_reference + " "
      body += owner_private_reference

      review.update_body(body, user)
      review = PullRequestReview.find(review.id)

      assert_includes review.body, "Hooray!"
      assert_includes review.body_html, %Q[href="#{user_private_issue.permalink}"]
      refute_includes review.body_html, %Q[href="#{owner_private_issue.permalink}"]
    end

    test "tracks references in the review body" do
      repo  = @pull.repository
      owner = repo.owner

      issue = create(:issue, repository: repo, user: owner)

      reference = [repo.name_with_owner, issue.number].join("#")
      body = "Hooray! a comment with some references: "
      body += reference + " "

      perform_enqueued_jobs(only: ProcessMentionedReferencesJob) do
        review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, state: PullRequestReview.state_value(:approved), body: body, submitted_at: Time.current)
        assert_includes review.body, "Hooray!"
        assert_includes review.body_html, %Q[href="#{issue.permalink}"]

        issue_reference = issue.reload.references.first
        assert_equal issue_reference.source, @pull.issue
      end
    end

    context "when interaction limits are enabled, viewer_cannot_update_reasons" do
      test "returns insufficient_access for non-collaborator author" do
        repo = @org_pull.repository
        review = create :pull_request_review, :approved, pull_request: @org_pull, user: @rando

        assert_empty review.async_viewer_cannot_update_reasons(@rando).sync

        interaction = RepositoryInteractionAbility.new(repo)
        interaction.set_ability(:collaborators_only, @admin)

        assert_equal [:insufficient_access], review.async_viewer_cannot_update_reasons(@rando).sync
      end

      test "returns empty list for collaborator author" do
        repo = @org_pull.repository
        review = create :pull_request_review, :approved, pull_request: @org_pull, user: @forker

        interaction = RepositoryInteractionAbility.new(repo)
        interaction.set_ability(:collaborators_only, @admin)

        assert_empty review.async_viewer_cannot_update_reasons(@forker).sync
      end
    end
  end

  context "async_on_behalf_of_teams" do
    test "returns all teams that the review was made on behalf of" do
      @org_pull.request_review_from(reviewers: [@owner, @team], actor: @owner)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, body: "blah")
      assert review.comment!

      assert_equal [@team], review.async_on_behalf_of_teams.sync
    end

    test "does not return `nil` for deleted teams" do
      @org_pull.request_review_from(reviewers: [@owner, @team], actor: @owner)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, body: "blah")
      assert review.comment!

      @team.delete

      assert_equal [], review.async_on_behalf_of_teams.sync
    end
  end

  context "#async_on_behalf_of_visible_teams_for" do
    test "returns all teams that the review was made on behalf of and which are visible to the given viewer" do
      @org_pull.request_review_from(reviewers: [@owner, @team], actor: @owner)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, body: "blah")
      assert review.comment!

      assert_equal [@team], review.async_on_behalf_of_visible_teams_for(@owner).sync
      assert_equal [], review.async_on_behalf_of_visible_teams_for(@rando).sync
    end

    test "strips duplicates from all teams that the review was made on behalf of" do
      @org_pull.request_review_from(reviewers: [@owner, @team, @team, @team], actor: @owner)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, body: "blah")
      assert review.comment!

      assert_equal [@team], review.async_on_behalf_of_visible_teams_for(@owner).sync
      assert_equal [], review.async_on_behalf_of_visible_teams_for(@rando).sync
    end

    test "does not return `nil` for deleted teams" do
      @org_pull.request_review_from(reviewers: [@owner, @team], actor: @owner)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, body: "blah")
      assert review.comment!

      @team.delete

      assert_equal [], review.async_on_behalf_of_visible_teams_for(@owner).sync
      assert_equal [], review.async_on_behalf_of_visible_teams_for(@rando).sync
    end
  end

  context "async_viewer_can_delete?" do
    test "returns true for ghost user reviews" do
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: (create :user), body: "blah")
      assert review.async_viewer_can_delete?(@owner).sync

      review.user.destroy
      review.reload
      assert review.async_viewer_can_delete?(@owner).sync
    end

    test "returns false when viewer does not have permission" do
      author = create(:user)
      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: author, body: "blah")
      # Anonymous user can't delete a comment
      refute review.async_viewer_can_delete?(nil).sync

      # Some rando can't delete a comment
      refute review.async_viewer_can_delete?((create :user)).sync

      # Normally the review author can delete a comment
      assert review.async_viewer_can_delete?(author).sync
      assert @pull.issue.lock(@owner)
      assert_predicate @pull.issue, :locked?
      # Can't delete a comment when the issue is locked for that user
      refute review.async_viewer_can_delete?(author).sync
    end
  end

  context "requesting review" do
    test "removes request when commented review created" do
      @pull.request_review_from(reviewers: [@owner], actor: @owner)
      request = @pull.review_requests.last
      assert_equal @pull.direct_review_request_for(@owner), request

      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "blah")
      assert review.comment!
      assert_predicate review, :commented?

      @pull.reload
      assert_nil @pull.direct_review_request_for(@owner)
    end

    test "removes request for team when commented review created" do
      @org_pull.request_review_from(reviewers: [@owner, @team], actor: @owner)
      assert @org_pull.review_requested_for?(@owner)
      assert @org_pull.review_requested_for?(@team)
      assert @org_pull.review_requested_for?(@forker)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, body: "blah")
      assert review.comment!
      assert_predicate review, :commented?

      @pull.reload
      refute @pull.review_requested_for?(@forker)
    end

    test "does not trigger a review_request_removed event on when approved review created" do
      @pull.request_review_from(reviewers: [@owner], actor: @owner)
      request = @pull.review_requests.last
      assert_equal @pull.direct_review_request_for(@owner), request

      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "blah")
      assert review.approve!

      assert_predicate review, :approved?
      @pull.reload
      assert_nil @pull.direct_review_request_for(@owner)

      request_event = @pull.events.last
      refute_equal "review_request_removed", request_event.event
    end

    test "does not remove request when reply review created" do
      @pull.request_review_from(reviewers: [@owner], actor: @owner)
      request = @pull.review_requests.last
      assert_equal @pull.direct_review_request_for(@owner), request

      review = @pull.reviews.create!(user: create(:user), head_sha: @pull.head_sha)
      thread = @pull.review_threads.build(pull_request_review: review) # autosaved by comment
      thread.build_first_comment(
        body: "ship it",
        path: "aquaman.txt",
        line: 21,
      ).save!
      review.comment!

      reply_review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha)
      thread.build_reply(
        pull_request_review: reply_review,
        user: @owner,
        body: "nice",
      ).save!
      reply_review.comment!

      reply_review.reload
      @pull.reload

      refute_nil  @pull.direct_review_request_for(@owner)
      assert_equal @pull.direct_review_request_for(@owner), request
    end

    test "does not remove request for team when commented review created by PR author" do
      @team.add_member @admin
      @org_pull.request_review_from(reviewers: [@owner, @team], actor: @owner)
      assert @org_pull.review_requested_for?(@owner)
      assert @org_pull.review_requested_for?(@team)
      assert @org_pull.review_requested_for?(@forker)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @admin, body: "blah")
      assert review.comment!
      assert_predicate review, :commented?

      @pull.reload
      assert @org_pull.review_requested_for?(@owner)
      assert @org_pull.review_requested_for?(@team)
      assert @org_pull.review_requested_for?(@forker)
    end

    test "removes request when approval reply review created" do
      @pull.request_review_from(reviewers: [@owner], actor: @owner)
      request = @pull.review_requests.last
      assert_equal @pull.direct_review_request_for(@owner), request

      review = @pull.reviews.create!(user: create(:user), head_sha: @pull.head_sha)
      thread = @pull.review_threads.build(pull_request_review: review) # autosaved by comment
      thread.build_first_comment(
        body: "ship it",
        path: "aquaman.txt",
        line: 21,
      ).save!
      review.comment!

      reply_review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha)
      thread.build_reply(
        pull_request_review: reply_review,
        user: @owner,
        body: "nice",
      ).save!

      reply_review.approve!
      reply_review.reload

      @pull.reload
      assert_nil @pull.direct_review_request_for(@owner)
    end

    test "unsets deferred boolean when review is fulfilled" do
      @pull.request_review_from(reviewers: [@owner], actor: @owner)
      request = @pull.review_requests.last
      request.update(deferred: true)
      assert_equal @pull.direct_review_request_for(@owner), request

      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @owner, body: "blah")
      review.comment!

      request.reload
      refute_predicate request, :deferred?
    end
  end

  context "#pull_request_has_changed?" do
    test "is false if the review head sha matches the pull head sha" do
      review = create(:pull_request_review,
        pull_request: @pull,
        user: @pull.user,
        head_sha: @pull.head_sha,
        state: 1
      )

      refute review.pull_request_has_changed?
    end

    test "is true if the review head sha precedes the pull head sha" do
      review = create(:pull_request_review,
        pull_request: @pull,
        user: @pull.user,
        head_sha: @pull.changed_commit_oids[-2],
        state: 1
      )

      assert review.pull_request_has_changed?
    end
  end

  context "#pull_request_oids_since" do
    test "returns all changed oids if force pushed and head_sha no longer exists" do
      review = create(:pull_request_review,
        pull_request: @pull,
        user: @pull.user,
        head_sha: @pull.head_sha.reverse,
        state: 1
      )

      assert_equal @pull.changed_commit_oids, review.pull_request_oids_since
    end

    test "returns an empty array if the review is on the pull request HEAD" do
      review = create(:pull_request_review, pull_request: @pull,
        user: @pull.user,
        head_sha: @pull.head_sha,
        state: 1
      )

      assert_equal [], review.pull_request_oids_since
    end

    test "returns an array of OID strings after the review's head_sha" do
      review = create(:pull_request_review, pull_request: @pull,
        user: @pull.user,
        head_sha: @pull.changed_commit_oids.first,
        state: 1
      )

      @pull.reload
      assert_equal @pull.changed_commit_oids[1..-1], review.pull_request_oids_since
    end
  end

  context "#applies_to_current_diff?" do
    test "returns true if the head_sha appears on the pull request" do
      review = create(:pull_request_review,
        pull_request: @pull,
        user: @pull.user,
        head_sha: @pull.head_sha,
        state: 1
      )
      assert review.applies_to_current_diff?

      review = create(:pull_request_review,
        pull_request: @pull,
        user: @pull.user,
        head_sha: @pull.changed_commit_oids.first,
        state: 1
      )
      assert review.applies_to_current_diff?
    end

    test "returns false if the head_sha no longer appears on the pull request" do
      review = create(:pull_request_review,
        pull_request: @pull,
        user: @pull.user,
        head_sha: @pull.head_sha.reverse,
        state: 1
      )

      refute review.applies_to_current_diff?
    end

    test "does not raise an error if the head_sha is missing in git" do
      review = create(:pull_request_review,
        pull_request: @pull,
        user: @pull.user,
        head_sha: @pull.head_sha.reverse,
        state: 1
      )

      Rugged::Repository.any_instance.stubs(:lookup).raises(GitRPC::ObjectMissing.new)
      refute review.applies_to_current_diff?
    end
  end

  context "#body_html" do
    test "handles poorly formed commit mention url with unicode characters" do
      body = "https://github.com/foo/bar/commit/acd1234の[これ](https://github.com/foo/bar/pull/95/commits)か"

      review = @pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @forker, body: body)

      assert_nothing_raised do
        review.body_html
      end
    end
  end

  context "#notifications_summary_title" do
    test "pending review" do
      review = create(:pull_request_review, pull_request: @pull, user: @owner)

      assert_raises PullRequestReview::InvalidStateForSummary do
        review.notifications_summary_title
      end
    end

    test "comment review" do
      review = create(:pull_request_review, pull_request: @pull, user: @owner, body: "LGTM")
      assert review.comment!

      assert_equal "@#{@owner} commented on this pull request.", review.notifications_summary_title
    end

    test "approving review" do
      review = create(:pull_request_review, pull_request: @pull, user: @owner)
      assert review.approve!

      assert_equal "@#{@owner} approved this pull request.", review.notifications_summary_title
    end

    test "changes requested review" do
      review = create(:pull_request_review, pull_request: @pull, user: @owner)
      assert review.request_changes!

      assert_equal "@#{@owner} requested changes on this pull request.", review.notifications_summary_title
    end

    test "dismissed review" do
      review = create(:pull_request_review, pull_request: @pull, user: @owner)
      assert review.request_changes!
      assert review.dismiss!(@forker, message: "No thanks")

      assert_equal "@#{@owner} dismissed review on this pull request.", review.notifications_summary_title
    end
  end

  context "#belongs_to_spammy_content?" do
    test "returns true if associated pull request is spammy", spammy_only: true do
      @forker.mark_as_spammy
      @pull.save!

      review = create(:pull_request_review, pull_request: @pull, user: @owner)

      assert review.belongs_to_spammy_content?
    end
  end unless GitHub.enterprise? # Spammy users don't exist in Enterprise.

  test "rate limited per user" do
    enable_content_creation_rate_limiting
    pull = create(:pull_request, :disable_disk_access)
    user = create(:user)

    expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
    limit = 2

    with_monolith_rate_limiter_redis_enabled do
      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
          limit.times { pull.reviews.create!(user: user, body: "cool", head_sha: pull.head_sha, state: :commented) }

          review = pull.reviews.build(user: user, body: "still cool", head_sha: pull.head_sha, state: :commented)

          refute_predicate review, :valid?
          assert_equal expected_errors, review.errors.full_messages
        end
      end
    end
  end

  test "private repos are rate limited" do
    enable_content_creation_rate_limiting
    pull = create(:pull_request, :disable_disk_access)
    pull.repository.toggle_visibility(actor: pull.repository.owner)
    assert pull.repository.private?

    user = create(:user)

    expected_errors = [GitHub::RateLimitedCreation::ERROR_MESSAGE]
    limit = 2

    with_cache_enabled do
      Timecop.freeze do
        GitHub::RateLimitedCreation.use_custom_limits(user_minute: limit) do
          limit.times { pull.reviews.create!(user: user, body: "cool", head_sha: pull.head_sha, state: :commented) }

          review = pull.reviews.build(user: user, body: "still cool", head_sha: pull.head_sha, state: :commented)

          refute_predicate review, :valid?
          assert_equal expected_errors, review.errors.full_messages
        end
      end
    end
  end

  context "update pull request counters" do
    test "don't update the counters when a review still pending" do
      @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "hello")

      assert_reviews nil, @pull
    end

    test "don't update the counters when a review is approved with no body" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha)
      review.approve!

      assert_reviews 0, @pull
    end

    test "approving a review should update the counters" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "approved")
      review.approve!

      assert_reviews 1, @pull
    end

    test "updating the body should increase or decrease the counters" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "approved")
      review.comment!
      assert_reviews 1, @pull

      # ensure to decrement the value
      review.update_attribute(:body, nil)
      assert_reviews 0, @pull

      # should increment again.
      review.update_attribute(:body, "approved again :)")
      assert_reviews 1, @pull

      # ensure that the decrement won't be negative
      review.update_attribute(:body, "")
      assert_reviews 0, @pull
    end

    test "must update the counters when a review is submitted" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "hello")
      review.comment!

      assert_reviews 1, @pull
    end

    test "must update the counters when a request change is required" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "hello")

      review.request_changes!
      assert_reviews 1, @pull
    end

    test "must update the counters when a review is destroyed" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "hello")

      review.comment!
      assert_reviews 1, @pull

      review.destroy!
      assert_reviews 0, @pull
    end

    test "don't update the counter when a review is dismissed" do
      review = @pull.reviews.create!(user: @owner, head_sha: @pull.head_sha, body: "hello")

      review.approve!
      assert_reviews 1, @pull

      review.dismiss!(@owner, message: "dismiss an approval")
      assert_reviews 1, @pull
    end
  end

  test "creating a record sets the repository ID" do
    review = create(:pull_request_review, pull_request: @pull)

    refute_nil @pull.repository.id
    # Note that we have to explicitly use attributes here as there's a getter
    # method that returns the ID from the repository. This getter will be
    # dropped in https://github.com/github/data-partitioning/issues/432.
    assert_equal review.attributes["repository_id"], @pull.repository.id
  end

  def assert_reviews(value, pull)
    pull.reload
    assert_nil pull.reviews_with_body_count if value.nil?
    assert_equal value, pull.reviews_with_body_count unless value.nil?
  end

  context "prelude_thread_comment_ids" do
    test "includes comments left as replies to a comment in this review" do
      review, comment = create_review_with_comment
      comment.save!
      review.comment!

      reply_only_review = create(:pull_request_review, pull_request: review.pull_request, body: nil)
      reply = comment.pull_request_review_thread.build_reply(
        pull_request_review: reply_only_review,
        user: reply_only_review.user,
        body: "reply"
      )
      reply.save!
      reply_only_review.comment!

      assert_includes review.prelude_thread_comment_ids(review.user), reply.id
    end

    test "includes review comments left as part of this review" do
      review, comment = create_review_with_comment
      assert_includes review.prelude_thread_comment_ids(review.user), comment.id
    end
  end

  test "callbacks are accounted for in DeletePullRequestReviewCommentOrchestration, CreateReplyPullRequestReviewCommentOrchestration, and CreateNewPullRequestReviewCommentOrchestration" do
    base_message =
"If this change applies to a callback invoked when creating or deleting a
comment, please ensure that it is applied to the orchestrations responsible
for deleting a comment, creating a new comment, or creating a reply"

    expected_callbacks_and_counts = {
      validate: 27,
      validation: 5,
      initialize: 0,
      find: 0,
      touch: 1,
      save: 9,
      create: 12,
      update: 12,
      destroy: 1,
      commit: 15,
      rollback: 0,
      before_commit: 0,
    }

    unless PullRequestReview.__callbacks.keys == expected_callbacks_and_counts.keys
      fail "New callback type introduced on the PullRequestReview model. \n#{base_message}"
    end

    expected_callbacks_and_counts.each do |name, count|
      assert_equal count, PullRequestReview.send("_#{name}_callbacks".to_sym).count, callback_count_message(name, count, PullRequestReview.send("_#{name}_callbacks".to_sym).count, base_message)
    end
  end

  context "events" do
    test "instruments hydro.schemas.events_platform.v0.Tier1Event hydro event when pull request review is submitted and events_v2_pull_request_enabled feature flag is enabled", skip_with_all_emus: true do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
          Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

          actor = create :user
          repository = create(:repository, from_example: :pull_request_fork)

          repo_actor = Events::ParentAsActor.repo_actor(repository.id)
          enable_feature_flag(:events_v2_owner_enabled, repo_actor)
          enable_feature_flag(:events_v2_pull_request_review_submitted_enabled, repo_actor)
          disable_feature_flag(:events_v2_pull_request_review_submitted_validation_enabled)

          events = subscribe "pull_request_review.submit"

          pull_request = create :pull_request, repository: repository
          pull_request_review = create :pull_request_review, pull_request: pull_request, user: actor, body: "Fuga esse fugit. Aut voluptatum natus. Tenetur ea repellat."
          pull_request_review.approve!

          metadata = {
            github_request_id: GitHub.context[:request_id],
            otel_trace_id: GitHub.current_span.context.hex_trace_id,
            tracked_writes: nil,
            spammy_user_acting_outside_own_repos: false,
            disabled_for_import: false,
          }

          graphql_next_global_id_prr = GitHub.enterprise? ? pull_request_review.global_relay_id : pull_request_review.next_global_id
          graphql_next_global_id_pr = GitHub.enterprise? ? pull_request.global_relay_id : pull_request.next_global_id
          graphql_next_global_id_user = GitHub.enterprise? ? actor.global_relay_id : actor.next_global_id

          message = {
            guid: mock_guid,
            type: :EVENT_TYPE_PULL_REQUEST_REVIEW,
            action: :EVENT_ACTION_SUBMITTED,
            target: {
              primary_entity: {
                type: :ENTITY_TYPE_PULL_REQUEST_REVIEW,
                id: pull_request_review.id.to_s,
                graphql_global_relay_id: pull_request_review.global_relay_id,
                graphql_next_global_id: graphql_next_global_id_prr,
              },
              related_entities: [{
                type: :ENTITY_TYPE_PULL_REQUEST,
                id: pull_request.id.to_s,
                graphql_global_relay_id: pull_request.global_relay_id,
                graphql_next_global_id: graphql_next_global_id_pr,
              }],
            },
            triggered_at: pull_request_review.submitted_at,
            actor: {
              type: :ENTITY_TYPE_USER,
              id: actor.id.to_s,
              graphql_global_relay_id: actor.global_relay_id,
              graphql_next_global_id: graphql_next_global_id_user,
            },
            attachment: nil,
            target_repository_id: repository.id,
            target_organization_id: repository&.organization_id,
            target_business_id: repository&.organization&.business&.id,
            flags: {
              webhook_flags: {
                webhook_deliveries_enabled: { value: true },
                events_v2_validation_enabled: { value: false }
              }
            }
          }
          # ignoring the metadata compare with ignore_extra_keys:true while asserting the hydro message
          assert_hydro_published(message, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.PullRequestReview", ignore_extra_keys: true)

          # Testing metadata separately
          hydro_message_metadata = hydro_messages(schema: "hydro.schemas.events_platform.v0.Tier1Event").first[:metadata]
          assert_equal false, hydro_message_metadata[:spammy_user_acting_outside_own_repos]
          assert_equal false, hydro_message_metadata[:disabled_for_import]
          assert_equal false, hydro_message_metadata[:otel_trace_id].blank?

          expected_payload = {
            spammy: false,
            pull_request_id: pull_request.id,
            pull_request_author: pull_request.user.login,
            pull_request_author_id: pull_request.user_id,
            pull_request_url: pull_request.permalink,
            pull_request_title: pull_request.title,
            repo: pull_request.repository.nwo,
            repo_id: pull_request.repository.id,
            public_repo: pull_request.repository.public?,
            issue_id: pull_request.issue.id,
            review_id: pull_request_review.id,
            new_reviewer_was_added: true,
            body: "Fuga esse fugit. Aut voluptatum natus. Tenetur ea repellat.",
            id: pull_request_review.id,
            actor: actor.login,
            actor_id: actor.id,
            state: PullRequestReview.state_value(:approved),
            allowed: false,
            flags: {
              hookshot_deliveries_enabled: false,
              events_v2_validation_enabled: false,
            }
          }

          assert event = events.pop, "expected a submit event to be triggered"
          assert_subset_hash expected_payload, event.payload
        end
      end
    end

    test "instruments hydro.schemas.events_platform.v0.Tier1Event hydro event when pull request review is submitted and events_v2_pull_request_review_submitted_validation_enabled feature flag is enabled", skip_with_all_emus: true do
      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
          GitHub.context.push(actor_ip: "3ffe:505:2::1")
          GitHub.context.push(user_agent: "test agent")

          mock_guid = "be5f4000-b6a0-11ee-8f69-b93ae6629aee"
          Events::Tier1EventPublisher.expects(:new_guid).returns(mock_guid).at_least_once

          actor = create :user
          repository = create(:repository, from_example: :pull_request_fork)

          repo_actor = Events::ParentAsActor.repo_actor(repository.id)
          enable_feature_flag(:events_v2_owner_enabled, repo_actor)
          disable_feature_flag(:events_v2_pull_request_review_submitted_enabled)
          enable_feature_flag(:events_v2_pull_request_review_submitted_validation_enabled, repo_actor)

          events = subscribe "pull_request_review.submit"

          pull_request = create :pull_request, repository: repository
          pull_request_review = create :pull_request_review, pull_request: pull_request, user: actor, body: "Fuga esse fugit. Aut voluptatum natus. Tenetur ea repellat."
          pull_request_review.approve!

          metadata = {
            github_request_id: GitHub.context[:request_id],
            otel_trace_id: GitHub.current_span.context.hex_trace_id,
            tracked_writes: nil,
            spammy_user_acting_outside_own_repos: false,
            disabled_for_import: false,
          }

          graphql_next_global_id_prr = GitHub.enterprise? ? pull_request_review.global_relay_id : pull_request_review.next_global_id
          graphql_next_global_id_pr = GitHub.enterprise? ? pull_request.global_relay_id : pull_request.next_global_id
          graphql_next_global_id_user = GitHub.enterprise? ? actor.global_relay_id : actor.next_global_id

          message = {
            guid: mock_guid,
            type: :EVENT_TYPE_PULL_REQUEST_REVIEW,
            action: :EVENT_ACTION_SUBMITTED,
            target: {
              primary_entity: {
                type: :ENTITY_TYPE_PULL_REQUEST_REVIEW,
                id: pull_request_review.id.to_s,
                graphql_global_relay_id: pull_request_review.global_relay_id,
                graphql_next_global_id: graphql_next_global_id_prr,
              },
              related_entities: [{
                type: :ENTITY_TYPE_PULL_REQUEST,
                id: pull_request.id.to_s,
                graphql_global_relay_id: pull_request.global_relay_id,
                graphql_next_global_id: graphql_next_global_id_pr,
              }],
            },
            triggered_at: pull_request_review.submitted_at,
            actor: {
              type: :ENTITY_TYPE_USER,
              id: actor.id.to_s,
              graphql_global_relay_id: actor.global_relay_id,
              graphql_next_global_id: graphql_next_global_id_user,
            },
            attachment: nil,
            target_repository_id: repository.id,
            target_organization_id: repository&.organization_id,
            target_business_id: repository&.organization&.business&.id,
            flags: {
              webhook_flags: {
                webhook_deliveries_enabled: { value: false },
                events_v2_validation_enabled: { value: true }
              }
            }
          }
          # ignoring the metadata compare with ignore_extra_keys:true while asserting the hydro message
          assert_hydro_published(message, schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.PullRequestReview", ignore_extra_keys: true)

          # Testing metadata separately
          hydro_message_metadata = hydro_messages(schema: "hydro.schemas.events_platform.v0.Tier1Event").first[:metadata]
          assert_equal false, hydro_message_metadata[:spammy_user_acting_outside_own_repos]
          assert_equal false, hydro_message_metadata[:disabled_for_import]
          assert_equal false, hydro_message_metadata[:otel_trace_id].blank?

          expected_payload = {
            spammy: false,
            pull_request_id: pull_request.id,
            pull_request_author: pull_request.user.login,
            pull_request_author_id: pull_request.user_id,
            pull_request_url: pull_request.permalink,
            pull_request_title: pull_request.title,
            repo: pull_request.repository.nwo,
            repo_id: pull_request.repository.id,
            public_repo: pull_request.repository.public?,
            issue_id: pull_request.issue.id,
            review_id: pull_request_review.id,
            new_reviewer_was_added: true,
            body: "Fuga esse fugit. Aut voluptatum natus. Tenetur ea repellat.",
            id: pull_request_review.id,
            actor: actor.login,
            actor_id: actor.id,
            state: PullRequestReview.state_value(:approved),
            allowed: false,
            flags: {
              hookshot_deliveries_enabled: true,
              events_v2_validation_enabled: true,
            }
          }

          assert event = events.pop, "expected a submit event to be triggered"
          assert_subset_hash expected_payload, event.payload
        end
      end
    end

    test "does not instrument hydro.schemas.events_platform.v0.Tier1Event hydro event when pull request review is submitted and feature flag is disabled", skip_with_all_emus: true do
      disable_feature_flag(:events_v2_owner_enabled)

      now = Time.now.beginning_of_day

      Timecop.freeze(now) do
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")

        events = subscribe "pull_request_review.submit"

        actor = create :user
        repository = create(:repository, from_example: :pull_request_fork)

        pull_request = create :pull_request, repository: repository
        pull_request_review = create :pull_request_review, pull_request: pull_request, user: actor
        pull_request_review.approve!

        refute_hydro_messages(schema: "hydro.schemas.events_platform.v0.Tier1Event", topic: "events_platform.v0.PullRequestReview")
        assert_equal 0, GitHub.dogstats.distributions("webhooks.hydro_publish.duration", tags: ["event_type:pull_request_review", "action:submitted"]).length

        expected_payload = {
          flags: {
            hookshot_deliveries_enabled: true,
            events_v2_validation_enabled: false,
          }
        }

        assert event = events.pop, "expected a submit event to be triggered"
        assert_subset_hash expected_payload, event.payload
      end
    end
  end
end

class PullRequestReviewReviewersTest < GitHub::TestCase
  include PlatformTestHelpers::InterfaceHelpers

  # Codeowners does not yet seem to work with EMUs because the user look up is done
  # by logins in the CODEOWNERS file but the users in the database have
  # postfixed usernames

  fixtures do
    @owner = create(:user, login: "owner", plan: "micro")
    @org_user = create(:user)
    @rando = create(:user, skip_enterprise_managed_user: true)

    @org = create :organization, login: "acme", admin: @owner
    @team = create(:team, organization: @org, name: "team_dog", privacy: :closed)
    @org_repo = create(:repository, owner: @org, from_example: :pull_request_source)
    @org_repo.add_member @org_user, action: :write
    @org_repo.add_member @owner, action: :write
    @team.add_member @org_user, adder: @owner
    @team.add_repository(@org_repo, :push)

    @org_pull = create(:pull_request,
      repository: @org_repo,
      user: @owner,
      base_repository: @org_repo,
      base_ref: "master",
      head_repository: @org_repo,
      head_ref: "master-merged-topic",
      issue: create(:issue, user: @owner, repository: @org_repo)
      )
  end

  context "#async_on_behalf_of_visible_reviewers" do
    test "returns codeowner team that the review was made on behalf of and which are visible to the given viewer" do
      @org_pull.request_review_from(reviewers: [@team], actor: @owner)
      request = @org_pull.review_requests.last
      request.reasons.create!(
        reason_type: "codeowners",
        codeowners_tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740",
        codeowners_path: "CODEOWNERS",
        codeowners_line: 1,
        codeowners_pattern: /foobar/,
      )

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @org_user, body: "blah")
      assert review.comment!

      owner_result = review.async_on_behalf_of_visible_reviewers(@owner).sync
      owner_result_on_behalf_of = owner_result.first
      assert_equal 1, owner_result.length
      assert_equal @team, owner_result_on_behalf_of[:reviewer]
      assert owner_result_on_behalf_of[:as_codeowner]

      rando_result = review.async_on_behalf_of_visible_reviewers(@rando).sync
      assert_equal [], rando_result
    end

    test "returns codeowner user that the review was made on behalf of" do
      @org_pull.request_review_from(reviewers: [@org_user], actor: @owner)
      request = @org_pull.review_requests.last
      request.reasons.create!(
        reason_type: "codeowners",
        codeowners_tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740",
        codeowners_path: "CODEOWNERS",
        codeowners_line: 1,
        codeowners_pattern: /foobar/,
      )

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @org_user, body: "blah")
      assert review.comment!

      owner_result = review.async_on_behalf_of_visible_reviewers(@owner).sync
      owner_result_on_behalf_of = owner_result.first
      assert_equal 1, owner_result.length
      assert_equal @org_user, owner_result_on_behalf_of[:reviewer]
      assert owner_result_on_behalf_of[:as_codeowner]

      rando_result = review.async_on_behalf_of_visible_reviewers(@rando).sync
      rando_result_on_behalf_of = rando_result.first
      assert_equal 1, rando_result.length
      assert_equal @org_user, rando_result_on_behalf_of[:reviewer]
      assert rando_result_on_behalf_of[:as_codeowner]
    end

    test "returns all teams that the review was made on behalf of and which are visible to the given viewer" do
      @org_pull.request_review_from(reviewers: [@owner, @team], actor: @owner)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @org_user, body: "blah")
      assert review.comment!

      owner_result = review.async_on_behalf_of_visible_reviewers(@owner).sync
      owner_result_on_behalf_of = owner_result.first
      assert_equal 1, owner_result.length
      assert_equal @team, owner_result_on_behalf_of[:reviewer]
      assert !owner_result_on_behalf_of[:as_codeowner]

      rando_result = review.async_on_behalf_of_visible_teams_for(@rando).sync
      assert_equal [], rando_result
    end

    test "strips duplicates from all teams that the review was made on behalf of" do
      @org_pull.request_review_from(reviewers: [@owner, @team, @team, @team], actor: @owner)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @org_user, body: "blah")
      assert review.comment!

      owner_result = review.async_on_behalf_of_visible_reviewers(@owner).sync
      assert_equal 1, owner_result.length
      assert_equal @team, owner_result[0][:reviewer]
      assert !owner_result[0][:as_codeowner]
    end

    test "does not return `nil` for deleted teams" do
      @org_pull.request_review_from(reviewers: [@owner, @team], actor: @owner)

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @org_user, body: "blah")
      assert review.comment!

      @team.delete

      assert_equal [], review.async_on_behalf_of_visible_teams_for(@owner).sync
      assert_equal [], review.async_on_behalf_of_visible_teams_for(@rando).sync
    end

    test "returns multiple teams that the review was made on behalf of with codeowner data" do
      team1 = create(:team, organization: @org, name: "team_cat", privacy: :closed)
      team1.add_member @org_user, adder: @owner
      team1.add_repository(@org_repo, :push)

      @org_pull.request_review_from(reviewers: [@team, team1], actor: @owner)
      request = @org_pull.review_requests.last
      request.reasons.create!(
        reason_type: "codeowners",
        codeowners_tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740",
        codeowners_path: "CODEOWNERS",
        codeowners_line: 1,
        codeowners_pattern: /foobar/,
      )

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @org_user, body: "blah")
      assert review.comment!

      owner_result = review.async_on_behalf_of_visible_reviewers(@owner).sync
      on_behalf_of_team = owner_result.first
      on_behalf_of_team1 = owner_result.second
      assert_equal 2, owner_result.length
      assert_equal @team, on_behalf_of_team[:reviewer]
      assert !on_behalf_of_team[:as_codeowner]
      assert_equal team1, on_behalf_of_team1[:reviewer]
      assert on_behalf_of_team1[:as_codeowner]

      rando_result = review.async_on_behalf_of_visible_reviewers(@rando).sync
      assert_equal [], rando_result
    end

    test "returns multiple teams and user codeowner that the review was made on behalf of" do
      team1 = create(:team, organization: @org, name: "team_cat", privacy: :closed)
      team1.add_member @org_user, adder: @owner
      team1.add_repository(@org_repo, :push)

      @org_pull.request_review_from(reviewers: [@team, team1, @org_user], actor: @owner)
      user_request = @org_pull.review_requests.first { |request| request.reviewer_type == "User" }
      user_request.reasons.create!(
        reason_type: "codeowners",
        codeowners_tree_oid: "725a9899207f0b65f51f27dba5eb77822edaf740",
        codeowners_path: "CODEOWNERS",
        codeowners_line: 1,
        codeowners_pattern: /foobar/,
      )

      review = @org_pull.reviews.create!(head_sha: "DEADBEEF" * 5, user: @org_user, body: "blah")
      assert review.comment!

      owner_result = review.async_on_behalf_of_visible_reviewers(@owner).sync
      on_behalf_of_team = owner_result[0]
      on_behalf_of_team1 = owner_result[1]
      on_behalf_of_org_user = owner_result[2]
      assert_equal 3, owner_result.length
      assert_equal @team, on_behalf_of_team[:reviewer]
      assert !on_behalf_of_team[:as_codeowner]
      assert_equal team1, on_behalf_of_team1[:reviewer]
      assert !on_behalf_of_team1[:as_codeowner]
      assert_equal @org_user, on_behalf_of_org_user[:reviewer]
      assert on_behalf_of_org_user[:as_codeowner]
    end
  end
end
