# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionEventTest < GitHub::TestCase
  include NewsiesHelper

  fixtures do
    @user = create(:verified_user)
    @actor = create(:verified_user)
    @discussion = create(:discussion)
    @event1 = create(:discussion_event, actor: @actor)
    @event2 = create(:discussion_event)
    @comment_event1 = create(:discussion_event, :comment, actor: @actor)
    @comment_event2 = create(:discussion_event, :comment)
  end

  setup do
    ActionMailer::Base.deliveries.clear
  end

  context "#async_old_repository_for" do
    test "resolves to nil when event is not a 'transferred' event" do
      refute_predicate @event1, :transferred?, "need a non-transferred event for this test"
      assert_nil @event1.async_old_repository_for(@user).sync
    end

    test "resolves to discussion's previous repo when viewer can see it" do
      user_who_transferred = create(:verified_user)
      old_repo = create(:private_repository, owner: user_who_transferred, has_discussions: true)
      old_repo.add_member(@user)
      transfer_event = create(:discussion_event, event_type: :transferred)
      create(:discussion_transfer, old_repository: old_repo,
        new_discussion_event: transfer_event, actor: user_who_transferred)

      result = transfer_event.async_old_repository_for(@user).sync

      assert_equal old_repo, result
    end

    test "resolves to nil when discussion's previous repo can't be seen by viewer" do
      user_who_transferred = create(:verified_user)
      old_repo = create(:private_repository, owner: user_who_transferred, has_discussions: true)
      transfer_event = create(:discussion_event, event_type: :transferred)
      create(:discussion_transfer, old_repository: old_repo,
        new_discussion_event: transfer_event, actor: user_who_transferred)

      result = transfer_event.async_old_repository_for(@user).sync

      assert_nil result
    end

    test "resolves to nil when discussion's previous repo has been deleted" do
      user_who_transferred = create(:verified_user)
      old_repo = create(:private_repository, owner: user_who_transferred, has_discussions: true)
      old_repo.add_member(@user)
      transfer_event = create(:discussion_event, event_type: :transferred)
      create(:discussion_transfer, old_repository: old_repo,
        new_discussion_event: transfer_event, actor: user_who_transferred)
      old_repo.delete

      result = transfer_event.async_old_repository_for(@user).sync

      assert_nil result
    end
  end

  context "#marked_or_unmarked_answer?" do
    test "true for answer_marked event" do
      event = build(:discussion_event, event_type: "answer_marked")
      assert_predicate event, :marked_or_unmarked_answer?
    end

    test "true for answer_unmarked event" do
      event = build(:discussion_event, event_type: "answer_unmarked")
      assert_predicate event, :marked_or_unmarked_answer?
    end

    test "false for locked event" do
      event = build(:discussion_event, event_type: "locked")
      refute_predicate event, :marked_or_unmarked_answer?
    end

    test "false for unlocked event" do
      event = build(:discussion_event, event_type: "unlocked")
      refute_predicate event, :marked_or_unmarked_answer?
    end
  end

  context "#readable_by?" do
    test "false when viewer has blocked event actor" do
      @user.block(@actor)
      refute @event1.readable_by?(@user)
    end

    test "false when event actor is spammy" do
      @actor.mark_as_spammy
      refute @event1.readable_by?(@user)
    end if GitHub.spamminess_check_enabled?

    test "false when viewer can't see the discussion the event is in" do
      private_event = create(:discussion_event, :private_discussion)
      refute private_event.readable_by?(@user)
    end

    test "true when viewer can see the discussion the event is in" do
      assert @event1.readable_by?(@user)
    end

    test "false when viewer can't read the associated comment" do
      private_comment_event = create(:discussion_event, :private_comment)
      refute private_comment_event.readable_by?(@user)
    end

    test "true when viewer can read the comment the event is about" do
      assert @comment_event1.readable_by?(@user)
    end
  end

  context "validations" do
    test "requires discussion" do
      event = DiscussionEvent.new
      refute_predicate event, :valid?
      assert_includes event.errors[:discussion], "must exist"
    end

    test "requires a repository" do
      event = DiscussionEvent.new
      refute_predicate event, :valid?
      assert_includes event.errors[:repository], "must exist"
    end

    test "requires an event type" do
      event = DiscussionEvent.new
      refute_predicate event, :valid?
      assert_includes event.errors[:event_type], "can't be blank"
    end
  end

  context "scopes" do
    test "for_organization returns events in discussions in repositories in the given organization" do
      org1 = create(:organization)
      org1_repo = create(:repository, owner: org1, has_discussions: true)
      org1_discussion = create(:discussion, repository: org1_repo)
      org1_event = create(:discussion_event, discussion: org1_discussion)
      org2 = create(:organization)
      org2_repo = create(:repository, owner: org2, has_discussions: true)
      org2_discussion = create(:discussion, repository: org2_repo)
      org2_event = create(:discussion_event, discussion: org2_discussion)

      result = DiscussionEvent.for_organization(org1)

      assert_includes result, org1_event
      refute_includes result, org2_event
    end

    test "for_organization can limit to discussion events in specific repositories" do
      org = create(:organization)
      discussion_events = {}
      repos = create_list(:repository, 3, owner: org, has_discussions: true).tap do |repos|
        repos.each do |repo|
          discussion = create(:discussion, repository: repo)
          discussion_events[repo.id] = create(:discussion_event, discussion: discussion)
        end
      end

      only_repo_ids = repos.first(2).map(&:id)
      expected_discussion_events = only_repo_ids.map { |id| discussion_events[id] }
      actual_discussion_events = DiscussionEvent.for_organization(org, only_repo_ids: only_repo_ids)

      assert_same_elements expected_discussion_events, actual_discussion_events
    end

    test "for_comment_authored_by returns events for comments left by the given user" do
      result = DiscussionEvent.for_comment_authored_by(@comment_event1.comment.user)

      assert_includes result, @comment_event1
      refute_includes result, @comment_event2
      refute_includes result, @event1
      refute_includes result, @event2
    end

    test "still_marked_as_answer returns events for marking a comment as the answer when that comment is still the answer today" do
      discussion = create(:discussion)
      used_to_be_answer = create(:discussion_comment, discussion: discussion)
      old_event = create(:discussion_event, discussion: discussion,
        comment: used_to_be_answer, event_type: :answer_marked)
      current_answer = create(:discussion_comment, discussion: discussion)
      discussion.update(chosen_comment_id: current_answer.id)
      current_event = create(:discussion_event, discussion: discussion,
        comment: current_answer, event_type: :answer_marked)

      result = DiscussionEvent.still_marked_as_answer

      assert_includes result, current_event
      refute_includes result, old_event
    end

    test "by_actor filters by the actor" do
      result = DiscussionEvent.by_actor(@event1.actor)

      assert_includes result, @comment_event1
      refute_includes result, @comment_event2
      assert_includes result, @event1
      refute_includes result, @event2
    end

    test "for_discussion filters by the discussion" do
      result = DiscussionEvent.for_discussion(@event1.discussion)

      refute_includes result, @comment_event1
      refute_includes result, @comment_event2
      assert_includes result, @event1
      refute_includes result, @event2
    end

    test "for_repository filters by the repository" do
      result = DiscussionEvent.for_repository(@event1.repository)

      refute_includes result, @comment_event1
      refute_includes result, @comment_event2
      assert_includes result, @event1
      refute_includes result, @event2
    end

    test "for_comment filters by the comment" do
      result = DiscussionEvent.for_comment(@comment_event1.comment)

      assert_includes result, @comment_event1
      refute_includes result, @comment_event2
      refute_includes result, @event1
      refute_includes result, @event2
    end
  end

  context "notifications" do
    test "sends notifications for closed event" do
      event = build(:discussion_event, :closed, discussion: @discussion)
      @discussion.subscribe(@user, "manual")

      perform_notification_jobs do
        event.save!
      end

      deliveries = ActionMailer::Base.deliveries
      assert_equal 1, deliveries.size
      mail = deliveries.last
      assert_match event.actor.login, mail.header["From"].to_s
      assert_match @user.login, mail.header["Cc"].to_s
      assert_match "Closed ##{event.discussion.number} as #{event.state_reason}.", text_part(mail)
      assert_match %r|Closed <a[^>]*href=\"#{@discussion.permalink}\"|, html_part(mail)
    end

    test "sends notifications for reopened event" do
      event = build(:discussion_event, :reopened, discussion: @discussion)
      @discussion.subscribe(@user, "manual")

      perform_notification_jobs do
        event.save!
      end

      deliveries = ActionMailer::Base.deliveries
      assert_equal 1, deliveries.size
      mail = deliveries.last
      assert_match event.actor.login, mail.header["From"].to_s
      assert_match @user.login, mail.header["Cc"].to_s
      assert_match "Reopened ##{event.discussion.number}.", text_part(mail)
      assert_match %r|Reopened <a[^>]*href=\"#{@discussion.permalink}\"|, html_part(mail)
    end

    test "does not send notification when discussion is converting" do
      @discussion.update!(
        state: :converting,
        issue: create(:issue, repository: @discussion.repository),
      )
      event = build(:discussion_event, :closed, discussion: @discussion)
      @discussion.subscribe(@user, "manual")

      perform_notification_jobs do
        event.save!
      end

      assert_equal 0, ActionMailer::Base.deliveries.size
    end

    test "does not send notification when discussion is transferring" do
      @discussion.update!(state: :transferring)
      event = build(:discussion_event, :closed, discussion: @discussion)
      @discussion.subscribe(@user, "manual")

      perform_notification_jobs do
        event.save!
      end

      assert_equal 0, ActionMailer::Base.deliveries.size
    end
  end

  private

  # Returns the text part of the email as a string
  def text_part(mail)
    mail.text_part.body.decoded
  end

  # Returns the html part of the email as a string
  def html_part(mail)
    mail.html_part.body.decoded
  end

  def perform_notification_jobs(&block)
    only = [
      Newsies::DeliverNotificationsJob,
      SubscribeAndNotifyJob,
    ]
    perform_enqueued_jobs(only:, &block)
  end
end
