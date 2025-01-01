# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueSummaryTest < GitHub::TestCase
  fixtures do
    @issue = create :issue
    @summary = create :issue_summary, issue: @issue
  end

  test "sets an initial state" do
    assert_equal IssueSummary::State.initial_state, IssueSummary.new.state
  end

  test "schedules on create" do
    assert_equal IssueSummary::State::Scheduled, @summary.state
  end

  context "#transition_scheduled!" do
    test "transitions from 'pending'" do
      @summary.transition_scheduled!
      assert_equal IssueSummary::State::Scheduled, @summary.state
    end

    test "transitions from 'failed'" do
      @summary.transition_in_progress!
      @summary.transition_failed!
      @summary.transition_scheduled!
      assert_equal IssueSummary::State::Scheduled, @summary.state
    end

    test "is idempotent" do
      @summary.transition_scheduled!
      @summary.transition_scheduled!
      assert_equal IssueSummary::State::Scheduled, @summary.state
    end

    test "raises for invalid transitions" do
      assert_raises IssueSummary::State::StateError do
        @summary.transition_complete!
      end
    end
  end

  context "#transition_in_progress!" do
    test "transitions from 'scheduled'" do
      @summary.transition_in_progress!
      assert_equal IssueSummary::State::InProgress, @summary.state
    end

    test "is idempotent" do
      @summary.transition_in_progress!
      @summary.transition_in_progress!
      assert_equal IssueSummary::State::InProgress, @summary.state
    end

    test "raises for invalid transitions" do
      @summary.transition_in_progress!
      @summary.transition_complete!

      assert_raises IssueSummary::State::StateError do
        @summary.transition_in_progress!
      end
    end
  end

  context "#transition_complete!" do
    test "transitions from 'in_progress'" do
      @summary.transition_in_progress!
      @summary.transition_complete!
      assert_equal IssueSummary::State::Complete, @summary.state
    end

    test "is idempotent" do
      @summary.transition_in_progress!
      @summary.transition_complete!
      @summary.transition_complete!
      assert_equal IssueSummary::State::Complete, @summary.state
    end

    test "raises for invalid transitions" do
      assert_raises IssueSummary::State::StateError do
        @summary.transition_complete!
      end
    end
  end

  context "#transition_failed!" do
    test "transitions from 'in_progress'" do
      @summary.transition_in_progress!
      @summary.transition_failed!
      assert_equal IssueSummary::State::Failed, @summary.state
    end

    test "is idempotent" do
      @summary.transition_in_progress!
      @summary.transition_failed!
      @summary.transition_failed!
      assert_equal IssueSummary::State::Failed, @summary.state
    end

    test "raises for invalid transitions" do
      assert_raises IssueSummary::State::StateError do
        @summary.transition_failed!
      end
    end
  end
end
