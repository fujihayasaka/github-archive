# typed: true
# frozen_string_literal: true

require "test_helper"

class AppStateTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
    @oauth_app = create(:oauth_application)
  end

  test "finds application from global relay id" do
    integration_app_state = ProximaAppRequest::AppState.new(@integration.global_relay_id, @integration.synchronization_fingerprint)
    oauth_app_state = ProximaAppRequest::AppState.new(@oauth_app.global_relay_id, @oauth_app.synchronization_fingerprint)

    assert_equal @integration, integration_app_state.application
    assert_equal @oauth_app, oauth_app_state.application
  end

  test "current? returns true when fingerprints match" do
    integration_app_state = ProximaAppRequest::AppState.new(@integration.global_relay_id, @integration.synchronization_fingerprint)
    oauth_app_state = ProximaAppRequest::AppState.new(@oauth_app.global_relay_id, @oauth_app.synchronization_fingerprint)

    assert integration_app_state.current?
    assert oauth_app_state.current?
  end

  test "current? returns false when fingerprints do not match" do
    @integration.update!(proxima_availability: :available)
    @oauth_app.update!(proxima_availability: :available)

    integration_app_state = ProximaAppRequest::AppState.new(@integration.global_relay_id, "different-fingerprint")
    oauth_app_state = ProximaAppRequest::AppState.new(@oauth_app.global_relay_id, "different-fingerprint")

    refute integration_app_state.current?
    refute oauth_app_state.current?
  end

  context "#unavailable?" do
    test "is false when is present and syncable" do
      @integration.update!(proxima_availability: :available)
      @oauth_app.update!(proxima_availability: :available)

      integration_app_state = ProximaAppRequest::AppState.new(@integration.global_relay_id, @integration.synchronization_fingerprint)
      oauth_app_state = ProximaAppRequest::AppState.new(@oauth_app.global_relay_id, @oauth_app.synchronization_fingerprint)

      refute_predicate integration_app_state, :unavailable?
      refute_predicate oauth_app_state, :unavailable?
    end

    test "is false when apps are present but not syncable" do
      refute_predicate @integration, :syncable_to_proxima?
      refute_predicate @oauth_app, :syncable_to_proxima?

      integration_app_state = ProximaAppRequest::AppState.new(@integration.global_relay_id, @integration.synchronization_fingerprint)
      oauth_app_state = ProximaAppRequest::AppState.new(@oauth_app.global_relay_id, @oauth_app.synchronization_fingerprint)

      assert_predicate integration_app_state, :unavailable?
      assert_predicate oauth_app_state, :unavailable?
    end

    test "is false when apps are gone" do
      @integration.destroy!
      @oauth_app.destroy!

      integration_app_state = ProximaAppRequest::AppState.new(@integration.global_relay_id, @integration.synchronization_fingerprint)
      oauth_app_state = ProximaAppRequest::AppState.new(@oauth_app.global_relay_id, @oauth_app.synchronization_fingerprint)

      assert_predicate integration_app_state, :unavailable?
      assert_predicate oauth_app_state, :unavailable?
    end

    test "unavailable apps are not outdated" do
      @integration.destroy!
      state = ProximaAppRequest::AppState.new(@integration.global_relay_id, @integration.synchronization_fingerprint)

      assert_predicate state, :unavailable?
      assert_predicate state, :current?

      refute_predicate state, :outdated?
    end
  end

  context "#current_state_hash" do
    test "returns hash for available application" do
      @integration.update!(proxima_availability: :available)
      state = ProximaAppRequest::AppState.new(@integration.global_relay_id, "different-fingerprint")

      expected_hash = {
        "global_relay_id" => @integration.global_relay_id,
        "fingerprint" => @integration.synchronization_fingerprint
      }

      assert_same_hash expected_hash, state.current_state_hash
    end

    test "returns hash for unavailable application" do
      @integration.update!(proxima_availability: :unavailable)
      state = ProximaAppRequest::AppState.new(@integration.global_relay_id, "received-fingerprint")

      expected_hash = {
        "global_relay_id" => @integration.global_relay_id,
        "fingerprint" => "received-fingerprint",
        "marked_for_deletion" => true
      }

      assert_same_hash expected_hash, state.current_state_hash
    end
  end
end
