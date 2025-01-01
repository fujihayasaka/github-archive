# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventCodeScanningAlertEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @actor = create(:user)
    @github_actor = create(:user, login: "github")
    @github_enterprise_actor = create(:user, login: "github-enterprise")
    @repo = create(:repository, :minimal)
  end

  setup do
    @event_args = {
      action: :created,
      repository_id: @repo.id,
      actor_id: @actor.id,
      alert_number: 4,
      ref: "master",
      commit_oid: "beef",
      result: {
        number: 4,
        most_recent_instance: { ref_name_bytes: "refs/heads/main" }
      }
    }
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::CodeScanningAlertEvent, :action, :repository_id, :alert_number
  end

  context "#target_repository" do
    test "returns the correct repo" do
      assert_equal @repo, event.target_repository
    end
  end

  context "#alert" do
    test "when feature flag is enabled, fetch alert data without calling Turboscan" do
      refute_nil event.alert
    end
  end

  context "#actor" do
    test "when actor not present returns GitHub", skip_enterprise: true do
      @event_args.delete :actor_id
      assert_equal event.actor, @github_actor
    end

    test "when actor is nil returns GitHub", skip_enterprise: true do
      @event_args[:actor_id] = nil
      assert_equal event.actor, @github_actor
    end

    test "when actor_id is present returns corresponding user object" do
      assert_equal event.actor, @actor
    end

    if GitHub.enterprise?
      test "when actor not present returns GitHub Enterprise" do
        @event_args.delete :actor_id
        assert_equal event.actor, @github_enterprise_actor
      end

      test "when actor is nil returns GitHub Enterprise" do
        @event_args[:actor_id] = nil
        assert_equal event.actor, @github_enterprise_actor
      end
    end
  end

  private

  def with_stub_stats
    stats = GitHub::MemoryDogstatsD.new
    GitHub.stubs(:dogstats).returns(stats)
    yield
    stats
  end

  def event
    @event ||= Hook::Event::CodeScanningAlertEvent.new(@event_args)
  end
end
