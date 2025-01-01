# typed: true
# frozen_string_literal: true

require "test_helper"

class Hook::Event::SubIssuesEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @org = create(:organization)
    @repo1 = create(:repository, owner: @org)
    @repo2 = create(:repository, owner: @org)
    @parent_issue = create(:issue, repository: @repo1)
    @sub_issue = create(:issue, repository: @repo2)
    @user = create(:user)
  end

  setup do
    GitHub.context.push(actor_id: @user.id)
  end

  def sub_issue_event(action: :sub_issue_added, parent_issue_id: @parent_issue.id, child_issue_id: @sub_issue.id, actor: @user)
    Hook::Event::SubIssuesEvent.new(
      action: action,
      parent_issue_id: parent_issue_id,
      child_issue_id: child_issue_id,
      actor_id: actor.id
    )
  end

  Hook::Event::SubIssuesEvent.actions.each do |action|
    test "on #{action}, fields are required" do
      assert_event_required_attributes Hook::Event::SubIssuesEvent, :action
      assert_event_required_attributes Hook::Event::SubIssuesEvent, :parent_issue_id
      assert_event_required_attributes Hook::Event::SubIssuesEvent, :child_issue_id
    end

    test "on #{action}, source and target are looked up using their issue ids" do
      event = sub_issue_event(action: action)

      assert_equal @parent_issue, event.parent_issue
      assert_equal @sub_issue, event.sub_issue
    end

    test "on #{action}, event is deliverable if all values are present" do
      event = sub_issue_event(action: action)
      assert event.deliverable?
    end

    test "on #{action}, event is not deliverable if all values are not present" do
      event = sub_issue_event(action: action)

      Issue.stubs(:find_by).with(id: @parent_issue.id).returns(nil)
      Issue.stubs(:find_by).with(id: @sub_issue.id).returns(nil)

      refute event.deliverable?
    end
  end

  context "#actor" do
    test "returns a User" do
      event = sub_issue_event(action: :sub_issue_added)
      assert_equal @user, event.actor
    end

    test "returns nil actor no longer exists" do
      event = sub_issue_event(action: :sub_issue_added)
      @user.destroy!

      assert_nil event.actor
    end
  end

  context "#target_repository" do
    test "returns parent issue repository for sub-issue actions" do
      event = sub_issue_event(action: :sub_issue_added)
      assert_equal @repo1, event.target_repository

      event = sub_issue_event(action: :sub_issue_removed)
      assert_equal @repo1, event.target_repository
    end

    test "returns sub-issue repository for parent issue actions" do
      event = sub_issue_event(action: :parent_issue_added)
      assert_equal @repo2, event.target_repository

      event = sub_issue_event(action: :parent_issue_removed)
      assert_equal @repo2, event.target_repository
    end
  end

  context "#parent_issue_repository" do
    test "returns parent_issue_repository for parent issue events" do
      event = sub_issue_event(action: :parent_issue_added)
      assert_equal @parent_issue.repository, event.parent_issue_repository
      event = sub_issue_event(action: :parent_issue_removed)
      assert_equal @parent_issue.repository, event.parent_issue_repository
    end

    test "returns nil for sub-issue events" do
      event = sub_issue_event(action: :sub_issue_added)
      assert_nil event.parent_issue_repository

      event = sub_issue_event(action: :sub_issue_removed)
      assert_nil event.parent_issue_repository
    end
  end

  context "#sub_issue_repository" do
    test "returns parent_issue_repository for sub-issue events" do
      event = sub_issue_event(action: :sub_issue_added)
      assert_equal @sub_issue.repository, event.sub_issue_repository
      event = sub_issue_event(action: :sub_issue_removed)
      assert_equal @sub_issue.repository, event.sub_issue_repository
    end

    test "returns nil for parent issue events" do
      event = sub_issue_event(action: :parent_issue_added)
      assert_nil event.sub_issue_repository

      event = sub_issue_event(action: :parent_issue_removed)
      assert_nil event.sub_issue_repository
    end
  end
end
