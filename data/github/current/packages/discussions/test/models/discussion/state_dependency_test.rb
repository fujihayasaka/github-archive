# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionStateDependencyTest < GitHub::TestCase
  include DiscussionsTestHelper
  include HydroTestHelpers

  fixtures do
    create_discussions_authz_fixtures

    @public_discussion = create(:discussion, :question, repository: @repo)
    private_discussion_author = create(:verified_user)
    @private_repo.add_member(private_discussion_author)
    @private_discussion = create(:discussion,
      repository: @private_repo,
      user: private_discussion_author,
    )

    @org_discussion = create(:discussion, repository: @org_repo)
    @org_private_discussion = create(:discussion, repository: @org_private_repo)
    @org_without_default_permission_repo_discussion = create(:discussion,
      repository: @org_without_default_permission_repo,
    )
    @org_without_default_permission_private_repo_discussion = create(:discussion,
      repository: @org_without_default_permission_private_repo,
    )
    @business_internal_discussion = create(:discussion, :question, repository: @business_internal_repo)

    if GitHub.organization_moderators_enabled?
      @org_moderator = create(:verified_user)
      @org.add_member(@org_moderator)
      @org.moderation.add_moderator(@org_moderator, actor: @org_admin)
    end
  end

  setup do
    @matrix = DiscussionsTestHelper::AccessMatrix.new(self)
    @matrix.setup_subjects(
      repo: @public_discussion,
      private_repo: @private_discussion,
      org_repo: @org_discussion,
      org_private_repo: @org_private_discussion,
      org_without_default_permission_repo: @org_without_default_permission_repo_discussion,
      org_without_default_permission_private_repo: @org_without_default_permission_private_repo_discussion,
      business_internal_repo: @business_internal_discussion,
    )
  end

  context "#closeable_by?" do
    test "requires triage+" do
      @matrix.user_scenarios(
        :closable_by?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for for discussion author" do
      assert @public_discussion.closable_by?(@public_discussion.user)
    end

    if GitHub.organization_moderators_enabled?
      test "true for org moderator" do
        assert @org.moderator?(@org_moderator)
        assert @org_discussion.closable_by?(@org_moderator)
      end

      test "false for org moderator in private repo" do
        assert @org.moderator?(@org_moderator)
        refute @org_private_discussion.closable_by?(@org_moderator)
      end
    end

    test "returns false for random user" do
      refute @public_discussion.closable_by?(@rando)
    end

    test "returns false for nil actor" do
      refute @public_discussion.closable_by?(nil)
    end
  end

  context "#reopenable_by?" do
    test "requires triage+" do
      @matrix.user_scenarios(
        :reopenable_by?,
        none: false,
        read: false,
        triage: true,
        write: true,
        maintain: true,
        admin: true,
      )
    end

    test "true for for discussion author if they previously closed it" do
      @public_discussion.close
      assert @public_discussion.reopenable_by?(@public_discussion.user)
    end

    test "false for for discussion author if they did not previously close it" do
      @public_discussion.close(actor: @repo.owner)
      refute @public_discussion.reopenable_by?(@public_discussion.user)
    end

    if GitHub.organization_moderators_enabled?
      test "true for org moderator" do
        assert @org.moderator?(@org_moderator)
        assert @org_discussion.reopenable_by?(@org_moderator)
      end

      test "false for org moderator in private repo" do
        assert @org.moderator?(@org_moderator)
        refute @org_private_discussion.reopenable_by?(@org_moderator)
      end
    end

    test "returns false for random user" do
      refute @public_discussion.reopenable_by?(@rando)
    end

    test "returns false for nil actor" do
      refute @public_discussion.reopenable_by?(nil)
    end
  end

  context "#close" do
    test "closes a discussion with default arguments" do
      assert_equal "open", @public_discussion.state
      assert_nil @public_discussion.state_reason
      assert_nil @public_discussion.closed_at

      assert @public_discussion.close

      assert_equal "closed", @public_discussion.state
      assert_equal "resolved", @public_discussion.state_reason
      refute_nil @public_discussion.closed_at
      event = @public_discussion.events.last
      assert_equal @public_discussion.user, event.actor
      assert_equal "closed", event.event_type
      assert_equal "resolved", event.state_reason
    end

    test "closes a discussion with a specified reason" do
      assert_equal "open", @public_discussion.state
      assert_nil @public_discussion.state_reason
      assert_nil @public_discussion.closed_at

      assert @public_discussion.close(reason: Discussion::StateReasonable::CloseReason::Outdated)

      assert_equal "closed", @public_discussion.state
      assert_equal "outdated", @public_discussion.state_reason
      refute_nil @public_discussion.closed_at
      event = @public_discussion.events.last
      assert_equal @public_discussion.user, event.actor
      assert_equal "closed", event.event_type
      assert_equal "outdated", event.state_reason
    end

    test "does nothing if already closed for specified reason" do
      assert @public_discussion.close(reason: Discussion::StateReasonable::CloseReason::Outdated)

      assert_no_difference("DiscussionEvent.count") do
        assert @public_discussion.close(reason: Discussion::StateReasonable::CloseReason::Outdated)
      end
    end

    test "creates new event if reason is changed" do
      assert @public_discussion.close(reason: Discussion::StateReasonable::CloseReason::Outdated)
      first_event = @public_discussion.events.last
      assert_equal @public_discussion.user, first_event.actor
      assert_equal "closed", first_event.event_type
      assert_equal "outdated", first_event.state_reason

      assert @public_discussion.close(reason: Discussion::StateReasonable::CloseReason::Resolved)
      event = @public_discussion.events.last
      refute_equal event.id, first_event.id
      assert_equal @public_discussion.user, event.actor
      assert_equal "closed", event.event_type
      assert_equal "resolved", event.state_reason
    end

    test "returns false if user is not authorized to close" do
      refute @public_discussion.close(actor: @rando)
    end

    test "instruments hydro event", skip_enterprise: true do
      Timecop.freeze do
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

        reset_hydro
        assert @public_discussion.close

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @public_discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(@public_discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(@public_discussion.repository.owner),
          actor_id: @public_discussion.user.id,
          actor: Hydro::EntitySerializer.user(@public_discussion.user),
          discussion_id: @public_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@public_discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          discussion_format: :DISCUSSION_FORMAT_QUESTION_ANSWER,
          category_id: @public_discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: Hydro::EntitySerializer.specimen_data(@public_discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(@public_discussion.body),
          state: :STATE_CLOSED,
          state_reason: :STATE_REASON_RESOLVED,
        }

        assert_hydro_published(message, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end
  end

  context "#reopen" do
    test "reopens a discussion with default actor" do
      assert @public_discussion.close
      assert_equal "closed", @public_discussion.state

      assert @public_discussion.reopen

      assert_equal "open", @public_discussion.state
      assert_equal "reopened", @public_discussion.state_reason
      event = @public_discussion.events.last
      assert_equal @public_discussion.user, event.actor
      assert_equal "reopened", event.event_type
      assert_equal "reopened", event.state_reason
    end

    test "reopens a discussion with specified actor" do
      assert @public_discussion.close
      assert_equal "closed", @public_discussion.state

      assert @public_discussion.reopen(actor: @repo.owner)

      assert_equal "open", @public_discussion.state
      assert_equal "reopened", @public_discussion.state_reason
      event = @public_discussion.events.last
      assert_equal @repo.owner, event.actor
      assert_equal "reopened", event.event_type
      assert_equal "reopened", event.state_reason
    end

    test "does nothing if already open" do
      assert_predicate @public_discussion, :open?
      assert_no_difference("DiscussionEvent.count") do
        assert @public_discussion.reopen(actor: @repo.owner)
        assert_predicate @public_discussion, :open?
      end
    end

    test "returns false if user is not authorized to reopen" do
      assert @public_discussion.close
      assert_equal "closed", @public_discussion.state
      refute @public_discussion.reopen(actor: @rando)
      assert_equal "closed", @public_discussion.state
    end

    test "returns false for author if they are not the latest closer" do
      assert @public_discussion.close(actor: @repo.owner)
      assert_equal "closed", @public_discussion.state
      refute @public_discussion.reopen(actor: @public_discussion.user)
      assert_equal "closed", @public_discussion.state
    end

    test "instruments a hydro event", skip_enterprise: true do
      assert @public_discussion.close

      Timecop.freeze do
        GitHub.context.push(actor_ip: "3ffe:505:2::1")
        GitHub.context.push(user_agent: "test agent")
        spamurai_form_signals = SpamuraiFormSignals.create(request_params: {})
        GitHub.context.push(spamurai_form_signals: spamurai_form_signals)

        reset_hydro
        assert @public_discussion.reopen

        message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          repository_id: @public_discussion.repository.id,
          repository: Hydro::EntitySerializer.repository(@public_discussion.repository),
          repository_owner: Hydro::EntitySerializer.user(@public_discussion.repository.owner),
          actor_id: @public_discussion.user.id,
          actor: Hydro::EntitySerializer.user(@public_discussion.user),
          discussion_id: @public_discussion.id,
          discussion: Hydro::EntitySerializer.discussion(@public_discussion),
          lock_status: :LOCK_STATUS_UNLOCKED,
          pin_status: :PIN_STATUS_UNPINNED,
          announcement: false,
          org_or_repo_level: :ORG_OR_REPO_LEVEL_REPO,
          action: :ACTION_DISCUSSION_UPDATED,
          action_timestamp: Time.now,
          discussion_format: :DISCUSSION_FORMAT_QUESTION_ANSWER,
          category_id: @public_discussion.category.id,
          converted_from_issue: false,
          converted_issue_id: nil,
          specimen_title: Hydro::EntitySerializer.specimen_data(@public_discussion.title),
          specimen_body: Hydro::EntitySerializer.specimen_data(@public_discussion.body),
          state: :STATE_OPEN,
          state_reason: :STATE_REASON_REOPENED,
        }

        assert_hydro_published(message, schema: "github.discussions.v2.Discussions")
        assert_hydro_messages(count: 1, schema: "github.discussions.v2.Discussions")
      end
    end
  end

  context "#closed_by" do
    test "returns latest closed event actor" do
      create(:discussion_event, event_type: :closed, state_reason: :resolved, actor: @rando)
      assert @public_discussion.close
      assert_equal @public_discussion.user, @public_discussion.closed_by
    end

    test "returns ghost if actor is deleted" do
      assert @public_discussion.close
      @public_discussion.user.destroy!
      assert_equal User.ghost, @public_discussion.closed_by
    end

    test "returns nil if discussion is not closed" do
      assert_predicate @public_discussion, :open?
      assert_nil @public_discussion.closed_by
    end
  end
end
