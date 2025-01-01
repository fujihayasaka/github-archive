# typed: true
# frozen_string_literal: true

require "test_helper"

class SlashCommandEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @organization = create(:organization)
    @user = create(:user)
    @repository = create(:repository, owner: @organization)
    @issue = create(:issue, user: @user, repository: @repository)
    @comment = create(:issue_comment, issue: @issue, user: @user, repository: @repository)
  end

  setup do
    @event = Hook::Event::SlashCommandEvent.new(command: "test", subject_id: @comment.id, subject_type: "IssueComment")
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::SlashCommandEvent, :command, :subject_id, :subject_type
  end

  context "#target" do
    test "returns the subject" do
      assert_equal @comment, @event.target
    end

    test "raises an error for an unsupported subject type" do
      SlashCommands.stub_const(:WEBHOOK_SUBJECT_TYPES, []) do
        assert_raises SlashCommands::UnsupportedSubjectType do
          @event.target
        end
      end
    end
  end

  context "#target_repository" do
    test "returns the subjects repository" do
      assert_equal @repository, @event.target_repository
    end
  end

  context "#actor" do
    test "returns the subject user if the subject is an issue comment" do
      assert_equal @user, @event.actor
    end
  end

  context "#deliverable?" do
    test "returns true if an actor and target organization are found" do
      assert @event.deliverable?
    end

    test "returns false if subject type is not supported" do
      SlashCommands.stub_const(:WEBHOOK_SUBJECT_TYPES, []) do
        refute @event.deliverable?
      end
    end

    test "returns false if actor isn't found" do
      @comment.update(user: nil)
      refute @event.deliverable?
    end

    test "returns false if target organization isn't found" do
      @repository.update(owner: @user)
      refute @event.deliverable?
    end
  end
end
