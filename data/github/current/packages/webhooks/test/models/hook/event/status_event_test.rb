# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventStatusEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @repo = create(:repository)
    reset_repo_root
    example_repo :mojombo_grit, @repo # rubocop:disable GitHub/UseFromExampleInRepositoryFactory

    @status = create(:status, repository: @repo)
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::StatusEvent, :status
  end

  context "#status" do
    test "returns the specified status" do
      event = Hook::Event::StatusEvent.new status: @status
      assert_equal @status, event.status
    end
  end

  context "#target_repository" do
    test "returns the repo for the specified status" do
      event = Hook::Event::StatusEvent.new status: @status
      assert_equal @status.repository, event.target_repository
    end
  end

  context "#actor" do
    test "returns the creator for the specified status" do
      event = Hook::Event::StatusEvent.new status: @status
      assert_equal @status.creator, event.actor
    end
  end

  context "#filterable_for_actions?" do
    test "filterable_for_actions? returns false when the repository isn't specified" do
      status = create(:status, repository: @repo)
      event = Hook::Event::StatusEvent.new status: status
      # We have to clear the repository after event creation
      status.repository = nil

      refute event.filterable_for_actions?
    end

    test "filterable_for_actions? returns true when the repository is specified" do
      event = Hook::Event::StatusEvent.new status: @status

      assert event.filterable_for_actions?
    end
  end
end
