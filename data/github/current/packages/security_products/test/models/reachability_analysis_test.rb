# typed: true
# frozen_string_literal: true

require "test_helper"

class ReachabilityAnalysisTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  fixtures do
    @org = create(:organization)
    @repo = create(:private_repository, :private, owner: @org)
  end

  test "can be created" do
    analysis = create(:reachability_analysis, repository: @repo)

    assert analysis.requested?
    assert_equal analysis, ReachabilityAnalysis.for_repository_id(@repo.id).first
  end

  test "cannot create new analysis if repo has an active analysis" do
    active_analysis = create(:reachability_analysis, repository: @repo)

    assert_raises_with_message ActiveRecord::RecordInvalid, "Validation failed: Repository already has an active reachability analysis" do
      create(:reachability_analysis, repository: @repo, sha: active_analysis.sha)
    end
    assert_equal 1, ReachabilityAnalysis.for_repository_id(@repo.id).count
  end

  context "state transitions" do
    test "can only transition to enqueued from requested" do
      assert_state_transitions("enqueued", %w(requested))
    end

    test "can only transition to running from enqueued" do
      assert_state_transitions("running", %w(enqueued))
    end

    test "can only transition to completed from running" do
      assert_state_transitions("completed", %w(running))
    end

    test "can only transition to incomplete from running" do
      assert_state_transitions("incomplete", %w(running))
    end

    test "can transition to failed from all states" do
      assert_state_transitions("failed", %w(requested enqueued running completed incomplete failed))
    end
  end

  test "gets deleted with repository" do
    analysis = create(:reachability_analysis, repository: @repo)
    other_analysis = create(:reachability_analysis)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [analysis]
      config.expect_not_destroyed = [other_analysis]
    end
  end

  def assert_state_transitions(transition_state, acceptable_origins)
    ReachabilityAnalysis::states.each do |origin_state, _|
      analysis = create(:reachability_analysis, state: origin_state)

      if origin_state.in?(acceptable_origins)
        transition_to_state(analysis, transition_state)
        assert_equal transition_state, analysis.state
      else
        assert_raises ReachabilityAnalysis::InvalidStateTransition do
          transition_to_state(analysis, transition_state)
        end
      end
    end
  end

  def transition_to_state(analysis, state)
    case state
    when "enqueued"
      analysis.set_enqueued
    when "running"
      analysis.set_running
    when "completed"
      analysis.set_completed
    when "incomplete"
      analysis.set_incomplete
    when "failed"
      analysis.set_failed
    end
  end
end
