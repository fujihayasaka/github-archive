# typed: true
# frozen_string_literal: true

require "test_helper"

class DependencyGraph::DataRefreshManagerTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @repository = create(:repository)
    @actor = create(:user)
  end

  setup do
    @data_refresh_manager = DependencyGraph::DataRefreshManager.new(@repository)
  end

  test "it is off cooldown by default" do
    refute_predicate @data_refresh_manager, :on_cooldown?
  end

  test "it is on cooldown when a mutex has been claimed" do
    assert GitHub::Redis::Mutex.new("dg:refresh:#{@repository.id}").lock
    assert_predicate @data_refresh_manager, :on_cooldown?
  end

  test "it triggers a refresh job that emits an event to Hydro and goes on cooldown" do
    refute_predicate @data_refresh_manager, :on_cooldown?

    perform_enqueued_jobs(only: RepositoryDependencyRedetectJob) do
      @data_refresh_manager.request_refresh!(actor: @actor)
    end

    with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
      assert_hydro_published_partial({
        repository: Hydro::EntitySerializer.repository(@repository),
        trigger: :RESET_TRIGGER_USER,
        action: :RESET_ACTION_REDETECT,
      }, schema: "github.dependencygraph.v1.ResetManifests")
    end

    assert_predicate @data_refresh_manager, :on_cooldown?
  end

  test "it refuses to queue a job if it is already on cooldown" do
    assert GitHub::Redis::Mutex.new("dg:refresh:#{@repository.id}").lock

    perform_enqueued_jobs(only: RepositoryDependencyRedetectJob) do
      @data_refresh_manager.request_refresh!(actor: @actor)
    end

    with_hydro_publisher(GitHub.aqueduct_fallback_hydro_publisher.hydro_publisher) do
      refute_hydro_messages(schema: "github.dependencygraph.v1.ResetManifests")
    end
  end

  context "#cooldown_ends_at" do
    test "it is nil by default" do
      assert_nil @data_refresh_manager.cooldown_ends_at
    end

    test "when a mutex exists it returns the interval between the given time and the mutex expiry" do
      # Manually set the mutex to a desired timestamp
      lock_key = "GitHub::Redis::Mutex-dg:refresh:#{@repository.id}"
      expiry_time = Time.now.utc + 30.minutes
      GitHub.job_coordination_redis.set(lock_key, expiry_time.to_f)

      assert_in_delta expiry_time, @data_refresh_manager.cooldown_ends_at, 1 # within a second
    end
  end
end
