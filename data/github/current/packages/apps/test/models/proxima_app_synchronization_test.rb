# typed: true
# frozen_string_literal: true

require "test_helper"

class ProximaAppSynchronizationTest < GitHub::TestCase

  fixtures do
    @first_party_app = create(:github_owned_integration, name: "some-first-party-app")
    create(:proxima_app_synchronization, local_app: @first_party_app, dotcom_global_id: "1p2q3r")

    @third_party_app = create(:integration, owner: make_proxima_third_party_apps_owner, name: "some-third-party-app")
    create(:proxima_app_synchronization, local_app: @third_party_app, dotcom_global_id: "3p4q5r")
  end

  test "creates" do
    app_sync = ProximaAppSynchronization.new(dotcom_global_id: "123abc", local_app_id: 1, local_app_type: "Integration", fingerprint: "somefancystring")

    assert_predicate app_sync, :valid?
  end

  context ".synchronized?" do
    if TestEnv.test_in_multitenancy_mode?
      test "is false for an app that has not been synchronized" do
        integration = create(:integration)
        refute ProximaAppSynchronization.synchronized?(integration), "Apps without proxima_app_synchronization records should not be marked as synchronized."
      end

      test "is true for first party app that has been synchronized" do
        assert ProximaAppSynchronization.synchronized?(@first_party_app), "Apps in a multi-tenant enterprise environment that have an associated proxima_app_synchronization record should be marked as synchronized."
      end

      test "is true for third party app that has been synchronized" do
        assert ProximaAppSynchronization.synchronized?(@third_party_app), "Apps in a multi-tenant enterprise environment that have an associated proxima_app_synchronization record should be marked as synchronized."
      end
    else
      test "is false in non-multi-tenant modes for first-party apps" do
        refute ProximaAppSynchronization.synchronized?(@first_party_app), "Only first-party apps in multi-tenant environments should ever be marked as synchronized"
      end

      test "is false in non-multi-tenant modes for third-party apps" do
        refute ProximaAppSynchronization.synchronized?(@third_party_app), "Only third-party apps in multi-tenant environments should ever be marked as synchronized"
      end
    end
  end

  context ".synchronized_first_party?" do
    if TestEnv.test_in_multitenancy_mode?
      test "is false for an app that has not been synchronized" do
        integration = create(:integration)
        refute ProximaAppSynchronization.synchronized_first_party?(integration), "Apps without proxima_app_synchronization records should not be marked as synchronized"
      end

      test "is false for an app that has been synchronized but is not owned by the first-party-apps owner" do
        refute ProximaAppSynchronization.synchronized_first_party?(@third_party_app), "Apps with proxima_app_synchronization records that are *not* owned by the first-party-apps owner should not be marked as synchronized (first-party)."
      end

      test "is true for an app that has been synchronized and is owned by the first-party-apps owner" do
        assert ProximaAppSynchronization.synchronized_first_party?(@first_party_app), "Apps in a multi-tenant enterprise environment that have an associated proxima_app_synchronization record and are owned by the first-party-apps owner should be marked as synchronized (first-party)."
      end
    else
      test "is false in non-multi-tenant modes" do
        refute ProximaAppSynchronization.synchronized_first_party?(@first_party_app), "Only first-party apps in multi-tenant environments should ever be marked as synchronized"
      end
    end
  end

  if TestEnv.test_in_multitenancy_mode?
    test ".synchronized_third_party? returns false for an app that has not been synchronized" do
      integration = create(:integration)
      refute ProximaAppSynchronization.synchronized_third_party?(integration), "Apps without proxima_app_synchronization records should not be marked as synchronized (third-party)."
    end

    test ".synchronized_third_party? returns false for an app that has been synchronized but is not owned by the third-party-apps owner" do
      refute ProximaAppSynchronization.synchronized_third_party?(@first_party_app), "Apps with proxima_app_synchronization records that are *not* owned by the third-party-apps owner should not be marked as synchronized (third-party)."
    end

    test ".synchronized_third_party? returns true for an app that has been synchronized and is owned by the third-party-apps owner" do
      assert ProximaAppSynchronization.synchronized_third_party?(@third_party_app), "Apps in a multi-tenant enterprise environment that have an associated proxima_app_synchronization record and are owned by the third-party-apps owner should be marked as synchronized (third-party)."
    end
  else
    test ".synchronized_third_party? returns false in non-multi-tenant modes" do
      refute ProximaAppSynchronization.synchronized_third_party?(@third_party_app), "Only third-party apps in multi-tenant environments should ever be marked as synchronized"
    end
  end
end
