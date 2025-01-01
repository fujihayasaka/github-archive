# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadDiscussionPayloadTest < GitHub::TestCase
  fixtures do
    @user = create(:verified_user)
    @repo = create(:repository, owner: @user, has_discussions: true)
    @discussion = create(:discussion, user: @user, repository: @repo)
    @discussion_comment = create(:discussion_comment, discussion: @discussion)

    @new_repo = create(:repository, owner: @user, has_discussions: true)

    @label = create(:label, name: "foo", repository: @repo)
  end

  context "when the discussion is created" do
    test "v3" do
      payload = build_discussion_payload(action: :created)
      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @discussion.id, v3[:discussion][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal @repo.name, v3[:repository][:name]
      assert_equal @user.id, v3[:sender][:id]
      assert_equal @user.login, v3[:sender][:login]
    end
  end

  context "when the discussion's title and body is updated" do
    test "v3" do
      changes = {
        old_body: "Body",
        body: "Changed Body",
        old_title: "Title",
        title: "Changed Title",
      }
      payload = build_discussion_payload(action: :edited, changes: changes)
      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @discussion.id, v3[:discussion][:id]
      assert_equal @user.id, v3[:sender][:id]
      assert_includes v3, :changes
    end
  end

  context "when the discussion's category is updated" do
    test "v3" do
      old_category = create(:discussion_category, repository: @repo)
      changes = { old_category_id: old_category.id, category_id: @discussion.category_id }
      payload = build_discussion_payload(action: :category_changed, changes: changes)
      v3 = payload.to_hash

      assert_equal :category_changed, v3[:action]
      assert_equal @discussion.id, v3[:discussion][:id]
      assert_equal old_category.id, v3[:changes][:category][:from][:id]
    end
  end

  context "when the discussion has been transferred from another repository" do
    test "the payload for the :transferred event includes the new discussion and new repository" do
      transfer = create(:discussion_transfer, old_discussion: @discussion, new_repository: @new_repo, actor: @user)
      new_discussion = transfer.new_discussion

      payload = build_discussion_payload(action: :transferred)
      v3 = payload.to_hash

      assert_equal :transferred, v3[:action]
      assert_equal @discussion.id, v3[:discussion][:id]
      assert_equal @repo.id, v3[:repository][:id]
      assert_equal new_discussion.id, v3[:changes][:new_discussion][:id]
      assert_equal @new_repo.id, v3[:changes][:new_repository][:id]
    end

    test "the payload for the :created event for the new discussion includes the old discussion and repository" do
      transfer = create(:discussion_transfer, old_discussion: @discussion, new_repository: @new_repo, actor: @user)
      new_discussion = transfer.new_discussion

      payload = build_discussion_payload(action: :created, discussion_id: new_discussion.id)
      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal new_discussion.id, v3[:discussion][:id]
      assert_equal @new_repo.id, v3[:repository][:id]
      assert_equal @discussion.id, v3[:changes][:old_discussion][:id]
      assert_equal @repo.id, v3[:changes][:old_repository][:id]
    end
  end

  context "when the discussion is marked answered or unanswered" do
    test "the payload for the :answered event includes the answer" do
      payload = build_discussion_payload(action: :answered, discussion_id: @discussion.id, answer_id: @discussion_comment.id)
      v3 = payload.to_hash

      assert_equal :answered, v3[:action]
      assert_equal @discussion_comment.id, v3[:answer][:id]
    end

    test "the payload for the :unanswered event includes the previous answer" do
      payload = build_discussion_payload(action: :unanswered, discussion_id: @discussion.id, answer_id: @discussion_comment.id)
      v3 = payload.to_hash

      assert_equal :unanswered, v3[:action]
      assert_equal @discussion_comment.id, v3[:old_answer][:id]
    end
  end

  context "when the discussion is labeled or unlabeled" do
    test "the payload for :label event includes the label" do
      payload = build_discussion_payload(action: :labeled, discussion_id: @discussion.id, label_id: @label.id)
      v3 = payload.to_hash

      assert_equal :labeled, v3[:action]
      assert_equal @label.id, v3[:label][:id]
    end

    test "the payload for :unlabel event includes the label" do
      payload = build_discussion_payload(action: :unlabeled, discussion_id: @discussion.id, label_id: @label.id)
      v3 = payload.to_hash

      assert_equal :unlabeled, v3[:action]
      assert_equal @label.id, v3[:label][:id]
    end
  end

  context "when the discussion is closed" do
    Discussion::StateReasonable::CloseReason.values.each do |value|
      test "reports event for discussion closed as #{value.serialize}" do
        assert @discussion.close(actor: @user, reason: value)
        payload = build_discussion_payload(action: :closed)
        v3 = payload.to_hash
        assert_equal :closed, v3[:action]
        assert_equal "closed", v3[:discussion][:state]
        assert_equal value.serialize, v3[:discussion][:state_reason]
      end
    end
  end

  context "when the discussion is reopened" do
    test "reports event for reopened" do
      assert @discussion.close(actor: @user)
      assert @discussion.reopen(actor: @user)
      payload = build_discussion_payload(action: :reopened)
      v3 = payload.to_hash
      assert_equal :reopened, v3[:action]
      assert_equal "open", v3[:discussion][:state]
      assert_equal Discussion::StateReasonable::StateReason::Reopened.serialize, v3[:discussion][:state_reason]
    end
  end

  def build_discussion_payload(attrs = {})
    default_attrs = {
      action: :created,
      discussion_id: @discussion.id,
      actor_id: @user.id,
    }

    event = Hook::Event::DiscussionEvent.new(attrs.reverse_merge(default_attrs))
    Hook::Payload::DiscussionPayload.new(event)
  end
end
