# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventDiscussionEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @user = create(:verified_user)
    @discussion = create :discussion, user: @user
    @discussion_comment = create :discussion_comment, discussion: @discussion
    @other_category = create :discussion_category, repository: @discussion.repository
    @label = create :label, name: "label"
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::DiscussionEvent, :action, :discussion_id, :actor_id
  end

  context "#discussion" do
    test "returns the specified discussion" do
      event = Hook::Event::DiscussionEvent.new action: :created, discussion_id: @discussion.id, actor_id: @user.id
      assert_equal @discussion, event.discussion
    end
  end

  context "#target_repository" do
    test "returns the repo of the specified user" do
      event = Hook::Event::DiscussionEvent.new action: :created, discussion_id: @discussion.id, actor_id: @user.id
      assert_equal @discussion.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::DiscussionEvent.new action: :created, discussion_id: @discussion.id, actor_id: @user.id
      assert_equal @user, event.actor
    end
  end

  context "#old_category" do
    test "returns nil if there are no category changes" do
      event = Hook::Event::DiscussionEvent.new action: :created, discussion_id: @discussion.id, actor_id: @user.id
      assert_nil event.old_category
    end

    test "returns the previous category if there are category changes" do
      event = Hook::Event::DiscussionEvent.new action: :created, discussion_id: @discussion.id, actor_id: @user.id,
        changes: { old_category_id: @other_category.id, category_id: @discussion.category_id }
      assert_equal @other_category, event.old_category
    end
  end

  context "#changes" do
    test "returns nil if no changes were made" do
      event = Hook::Event::DiscussionEvent.new action: :created, discussion_id: @discussion.id, actor_id: @user.id
      assert_nil event.changes
    end

    test "returns a hash with body changes if body changes were made" do
      event = Hook::Event::DiscussionEvent.new action: :edited, discussion_id: @discussion.id, actor_id: @user.id, changes: { old_body: "old body", body: "new body" }
      expected_changes = { body: { from: "old body" } }
      assert_equal expected_changes, event.changes
    end

    test "returns a hash with title changes if title changes were made" do
      event = Hook::Event::DiscussionEvent.new action: :edited, discussion_id: @discussion.id, actor_id: @user.id, changes: { old_title: "old title", title: "new title" }
      expected_changes = { title: { from: "old title" } }
      assert_equal expected_changes, event.changes
    end

    test "returns a hash with category changes if category changes were made" do
      old_category = create(:discussion_category, repository: @discussion.repository)
      event = Hook::Event::DiscussionEvent.new action: :edited, discussion_id: @discussion.id, actor_id: @user.id,
        changes: { old_category_id: old_category.id, category_id: @discussion.category_id }
      assert_equal old_category.id, event.changes[:category_id][:from]
    end
  end

  context "#deliverable?" do
    test "returns true" do
      event = Hook::Event::DiscussionEvent.new action: :created, discussion_id: @discussion.id, actor_id: @user.id
      assert_predicate event, :deliverable?
    end

    test "returns false for deleted discussion" do
      event = Hook::Event::DiscussionEvent.new action: :created, discussion_id: -1, actor_id: @user.id
      refute_predicate event, :deliverable?
    end
  end

  context "#answer" do
    test "returns nil if there are no answer changes" do
      event = Hook::Event::DiscussionEvent.new action: :created, discussion_id: @discussion.id, actor_id: @user.id
      assert_nil event.answer
    end

    test "returns the answer if there are answer changes" do
      event = Hook::Event::DiscussionEvent.new action: :answered, discussion_id: @discussion.id, actor_id: @user.id,
        answer_id: @discussion_comment.id
      assert_equal @discussion_comment, event.answer
    end
  end

  context ".description" do
    test "returns the right description" do
      assert_equal "Discussion created, edited, closed, reopened, pinned, unpinned, locked, unlocked,"\
      " transferred, answered, unanswered, labeled, unlabeled, had its category changed,"\
      " or was deleted.",
        Hook::Event::DiscussionEvent.description
    end
  end

  context "#label" do
    test "returns the added label" do
      event = Hook::Event::DiscussionEvent.new action: :labeled, discussion_id: @discussion.id, actor_id: @user.id, label_id: @label.id
      assert_equal @label, event.label
    end

    test "returns the removed label" do
      event = Hook::Event::DiscussionEvent.new action: :unlabeled, discussion_id: @discussion.id, actor_id: @user.id, label_id: @label.id
      assert_equal @label, event.label
    end

    test "nil returned if no label is specified" do
      event = Hook::Event::DiscussionEvent.new action: :labeled, discussion_id: @discussion.id, actor_id: @user.id
      refute event.label
    end
  end
end
