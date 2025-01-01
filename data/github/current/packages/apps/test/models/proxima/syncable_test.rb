# typed: true
# frozen_string_literal: true

require "test_helper"

class ProximaSyncableTest < GitHub::TestCase
  setup do
    @app = create(:oauth_application)
  end

  test "syncable_to_proxima? returns true for first party apps" do
    Apps::Internal.expects(:capable?).with(:proxima_first_party_sync, app: @app).returns(true)
    assert @app.syncable_to_proxima?
  end

  test "syncable_to_proxima? returns true for third party apps" do
    @app.expects(:available?).returns(true)
    assert @app.syncable_to_proxima?
  end

  test "syncable_to_proxima? returns false for third party apps that are not available" do
    @app.expects(:available?).returns(false)
    refute @app.syncable_to_proxima?
  end

  test "synchronized_dotcom_app? returns false when not in a multi-tenant enterprise" do
    GitHub.expects(:multi_tenant_enterprise?).returns(false)
    refute @app.synchronized_dotcom_app?
  end

  test "synchronized_dotcom_app? returns false when the app is not synchronized" do
    ProximaAppSynchronization.expects(:synchronized?).with(@app).returns(false)
    refute @app.synchronized_dotcom_app?
  end

  test "synchronized_dotcom_app? returns true when the app is synchronized" do
    ProximaAppSynchronization.expects(:synchronized?).with(@app).returns(true)
    assert @app.synchronized_dotcom_app?
  end

  test "synchronized_third_party_app? returns false when not in a multi-tenant enterprise" do
    GitHub.expects(:multi_tenant_enterprise?).returns(false)
    refute @app.synchronized_third_party_app?
  end

  test "synchronized_third_party_app? returns false when the app is not synchronized" do
    ProximaAppSynchronization.expects(:synchronized_third_party?).with(@app).returns(false)
    refute @app.synchronized_third_party_app?
  end

  test "synchronized_third_party_app? returns true when the app is synchronized" do
    ProximaAppSynchronization.expects(:synchronized_third_party?).with(@app).returns(true)
    assert @app.synchronized_third_party_app?
  end
end
