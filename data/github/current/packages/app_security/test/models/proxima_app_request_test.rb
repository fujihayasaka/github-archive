# typed: true
# frozen_string_literal: true

require "test_helper"

class ProximaAppRequestTest < GitHub::TestCase
  fixtures do
    @integration = create(:integration)
    @oauth_app = create(:oauth_application)
  end

  Registry = Apps::Internal::Registry

  context "first_party_app_ids_requesting_sync" do
    test "returns an array of apps that are capable of syncing with Proxima" do
      Registry.configure(
        app: @integration,
        app_alias: :test_integration_app,
        id: -> { @integration.id }, capabilities: { proxima_first_party_sync: true }
      )

      Registry.configure(
        app: @oauth_app,
        app_alias: :test_oauth_app,
        id: -> { @oauth_app.id }, capabilities: { proxima_first_party_sync: true }
      )

      apps = ProximaAppRequest.first_party_app_ids_requesting_sync

      assert apps.length > 1

      apps.each do |app|
        assert Apps::Internal.capable?(:proxima_first_party_sync, app: app)
      end
    ensure
      Registry.reset_configuration!
    end
  end

  context "from" do
    test "accepts array of states and instantiates AppStates" do
      states = [
        {
          "global_relay_id" => "1",
          "fingerprint" => "1"
        },
        {
          "global_relay_id" => "2",
          "fingerprint" => "2"
        }
      ]

      synch = ProximaAppRequest.from(states)

      assert_equal 2, synch.apps.length
    end
  end

  context "syncable" do
    test "returns apps that are missing from the request" do
      Registry.configure(
        app: @integration,
        app_alias: :test_integration_app,
        id: -> { @integration.id }, capabilities: { proxima_first_party_sync: true }
      )

      Registry.configure(
        app: @oauth_app,
        app_alias: :test_oauth_app,
        id: -> { @oauth_app.id }, capabilities: { proxima_first_party_sync: true }
      )

      up_to_date_app = create(:integration)
      Registry.configure(
        app: up_to_date_app,
        app_alias: :test_up_to_date_integration_app,
        id: -> { up_to_date_app.id }, capabilities: { proxima_first_party_sync: true }
      )

      synch = ProximaAppRequest.from([{
        "global_relay_id" => up_to_date_app.global_relay_id,
        "fingerprint" => up_to_date_app.synchronization_fingerprint
      }])
      missing = synch.syncable.map(&:global_relay_id)

      assert_includes missing, @integration.global_relay_id
      assert_includes missing, @oauth_app.global_relay_id
      refute_includes missing, up_to_date_app.global_relay_id
    ensure
      Registry.reset_configuration!
    end

    test "returns apps that are outdated from the request" do
      Registry.configure(
        app: @integration,
        app_alias: :test_integration_app,
        id: -> { @integration.id }, capabilities: { proxima_first_party_sync: true }
      )

      Registry.configure(
        app: @oauth_app,
        app_alias: :test_oauth_app,
        id: -> { @oauth_app.id }, capabilities: { proxima_first_party_sync: true }
      )

      up_to_date_app = create(:integration)
      Registry.configure(
        app: up_to_date_app,
        app_alias: :test_up_to_date_integration_app,
        id: -> { up_to_date_app.id }, capabilities: { proxima_first_party_sync: true }
      )

      synch = ProximaAppRequest.from([
        {
          "global_relay_id" => up_to_date_app.global_relay_id,
          "fingerprint" => "outofdate"
        },
        {
          "global_relay_id" => @integration.global_relay_id,
          "fingerprint" => @integration.synchronization_fingerprint
        }
      ])
      missing = synch.syncable.map(&:global_relay_id)

      refute_includes missing, @integration.global_relay_id
      assert_includes missing, @oauth_app.global_relay_id
      assert_includes missing, up_to_date_app.global_relay_id
    ensure
      Registry.reset_configuration!
    end

    test "ensures deletions are sent last", feature_enabled: :sync_deletions_to_proxima_apps do
      Registry.configure(
        app: @integration,
        app_alias: :test_integration_app,
        id: -> { @integration.id }, capabilities: { proxima_first_party_sync: true }
      )

      Registry.configure(
        app: @oauth_app,
        app_alias: :test_oauth_app,
        id: -> { @oauth_app.id }, capabilities: { proxima_first_party_sync: true }
      )

      up_to_date_app = create(:integration)
      Registry.configure(
        app: up_to_date_app,
        app_alias: :test_up_to_date_integration_app,
        id: -> { up_to_date_app.id }, capabilities: { proxima_first_party_sync: true }
      )

      outdated_global_id = "A_kwAAAA"
      synch = ProximaAppRequest.from([
        {
          "global_relay_id" => up_to_date_app.global_relay_id,
          "fingerprint" => "out-of-date"
        },
        {
          "global_relay_id" => outdated_global_id,
          "fingerprint" => @integration.synchronization_fingerprint
        }
      ])

      marked_for_deletion = synch.syncable.map(&:unavailable?)
      # 2 missing, 1 outdated, 1 marked for deletion
      assert_equal [false, false, false, true], marked_for_deletion
    ensure
      Registry.reset_configuration!
    end
  end

  context "missing" do
    test "returns apps that are missing from the request" do
      Registry.configure(
        app: @integration,
        app_alias: :test_integration_app,
        id: -> { @integration.id }, capabilities: { proxima_first_party_sync: true }
      )

      Registry.configure(
        app: @oauth_app,
        app_alias: :test_oauth_app,
        id: -> { @oauth_app.id }, capabilities: { proxima_first_party_sync: true }
      )

      synch = ProximaAppRequest.from([])
      missing = synch.missing.map(&:global_relay_id)

      assert_includes missing, @integration.global_relay_id
      assert_includes missing, @oauth_app.global_relay_id
    ensure
      Registry.reset_configuration!
    end
  end

  context "outdated" do
    test "returns 1p apps that are outdated from the request" do
      Registry.configure(
        app: @integration,
        app_alias: :test_integration_app,
        id: -> { @integration.id }, capabilities: { proxima_first_party_sync: true }
      )
      Registry.configure(
        app: @oauth_app,
        app_alias: :test_oauth_app,
        id: -> { @oauth_app.id }, capabilities: { proxima_first_party_sync: true }
      )
      third_party_app = create(:oauth_application, proxima_availability: "available")

      assert_predicate @integration, :syncable_first_party_app?
      assert_predicate @oauth_app, :syncable_first_party_app?
      assert_predicate third_party_app, :syncable_third_party_app?

      states = [
        {
          "global_relay_id" => @integration.global_relay_id,
          "fingerprint" => "foo"
        },
        {
          "global_relay_id" => @oauth_app.global_relay_id,
          "fingerprint" => "bar"
        },
        {
          "global_relay_id" => third_party_app.global_relay_id,
          "fingerprint" => "baz"
        }
      ]

      synch = ProximaAppRequest.from(states, party_type: ProximaAppHelper::FIRST_PARTY_TYPE)

      assert_equal 2, synch.outdated.length
      assert_includes synch.outdated.map(&:application), @integration
      assert_includes synch.outdated.map(&:application), @oauth_app
    end

    test "returns 3p apps that have outdated fingerprints" do
      @integration.update!(proxima_availability: "available")
      @oauth_app.update!(proxima_availability: "available")
      first_party_app = create(:oauth_application, proxima_availability: "available")
      Registry.configure(
        app: first_party_app,
        app_alias: :test_first_party_app,
        id: -> { first_party_app.id }, capabilities: { proxima_first_party_sync: true }
      )

      assert_predicate @integration, :syncable_third_party_app?
      assert_predicate @oauth_app, :syncable_third_party_app?
      assert_predicate first_party_app, :syncable_first_party_app?

      states = [
        {
          "global_relay_id" => @integration.global_relay_id,
          "fingerprint" => "foo"
        },
        {
          "global_relay_id" => @oauth_app.global_relay_id,
          "fingerprint" => "bar"
        },
        {
          "global_relay_id" => first_party_app.global_relay_id,
          "fingerprint" => first_party_app.synchronization_fingerprint
        }
      ]

      synch = ProximaAppRequest.from(states, party_type: ProximaAppHelper::THIRD_PARTY_TYPE)

      assert_equal 2, synch.outdated.length
      assert_includes synch.outdated.map(&:application), @integration
      assert_includes synch.outdated.map(&:application), @oauth_app
    end

    test "doesn't return apps that have up to date fingerprints" do
      @integration.update!(proxima_availability: "available")
      @oauth_app.update!(proxima_availability: "available")

      assert_predicate @integration, :syncable_third_party_app?
      assert_predicate @oauth_app, :syncable_third_party_app?

      states = [
        {
          "global_relay_id" => @integration.global_relay_id,
          "fingerprint" => @integration.synchronization_fingerprint
        },
        {
          "global_relay_id" => @oauth_app.global_relay_id,
          "fingerprint" => @oauth_app.synchronization_fingerprint
        }
      ]

      synch = ProximaAppRequest.from(states)

      assert_empty synch.outdated
    end
  end

  context "#marked_for_deletion" do
    test "returns unavailable 3p apps", feature_enabled: :sync_deletions_to_proxima_apps do
      states = [
        {
          "global_relay_id" => @integration.global_relay_id,
          "fingerprint" => "foo" # not important on deletions
        },
      ]

      @integration.destroy!

      request = ProximaAppRequest.from(states, party_type: ProximaAppHelper::THIRD_PARTY_TYPE)

      assert_equal 1, request.marked_for_deletion.size
      assert_predicate request.marked_for_deletion.first, :unavailable?
    end

    test "returns nothing", feature_disabled: :sync_deletions_to_proxima_apps do
      states = [
        {
          "global_relay_id" => @integration.global_relay_id,
          "fingerprint" => "foo" # not important on deletions
        },
      ]

      @integration.destroy!

      request = ProximaAppRequest.from(states, party_type: ProximaAppHelper::THIRD_PARTY_TYPE)

      assert_equal [], request.missing
      assert_equal [], request.outdated
      assert_equal [], request.marked_for_deletion
    end
  end
end
