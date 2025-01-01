# typed: true
# frozen_string_literal: true

require "test_helper"

class AppManifestTest < GitHub::TestCase
  fixtures do
    @first_party_integration = create_privileged_app_with_capabilities(capabilities: { proxima_first_party_sync: true }, properties: { proxima_sync_delegate: :DefaultDelegate })
    @first_party_oauth_app = create_privileged_app_with_capabilities(type: :oauth_application, capabilities: { proxima_first_party_sync: true }, properties: { proxima_sync_delegate: :DefaultDelegate })
  end

  test "returns an integration manifest with expected keys when integration has proxima_first_party_sync capability" do
    manifest = ProximaAppRequest::AppManifest.new(@first_party_integration).serialize_manifest
    ProximaAppRequest::AppManifest::INTEGRATION_ATTRIBUTES.each do |key|
      assert manifest.key?(key)
    end
  end

  test "returns an integration manifest with expected keys when integration has proxima_availability set to true" do
    integration = create(:integration, proxima_availability: :available)
    refute Apps::Privileged.capable?(:proxima_first_party_sync, app: integration)

    manifest = ProximaAppRequest::AppManifest.new(integration).serialize_manifest
    ProximaAppRequest::AppManifest::INTEGRATION_ATTRIBUTES.each do |key|
      assert manifest.key?(key)
    end
  end

  test "returns an empty hash for an integration without proxima_first_party_sync capability or proxima_availability set to false" do
    unsyncable_app = create_privileged_app_with_capabilities(inherits: [:first_party], capabilities: { proxima_first_party_sync: false }, properties: { proxima_availability: :unavailable })

    assert_raises_with_message(ProximaAppRequest::AttributeResolution::DelegateNotFound, "No delegate found for #{unsyncable_app.class} with ID #{unsyncable_app.id}") do
      ProximaAppRequest::AppManifest.new(unsyncable_app).serialize_manifest
    end
  end

  test "returns an oauth application manifest with expected keys when app has proxima_first_party_sync capability" do
    manifest = ProximaAppRequest::AppManifest.new(@first_party_oauth_app).serialize_manifest
    ProximaAppRequest::AppManifest::OAUTH_APPLICATION_ATTRIBUTES.each do |key|
      assert manifest.key?(key)
    end
  end

  test "returns an oauth application manifest with expected keys when app has has proxima_availability set to true" do
    app = create(:oauth_application, proxima_availability: :available)
    refute Apps::Privileged.capable?(:proxima_first_party_sync, app: app)

    manifest = ProximaAppRequest::AppManifest.new(app).serialize_manifest
    ProximaAppRequest::AppManifest::OAUTH_APPLICATION_ATTRIBUTES.each do |key|
      assert manifest.key?(key)
    end
  end

  test "INTEGRATION_ATTRIBUTES cannot include private keys" do
    refute_includes ProximaAppRequest::AppManifest::INTEGRATION_ATTRIBUTES, :private_keys, ":private_keys is a restricted attribute and cannot be included in the manifest. See https://thehub.github.com/epd/engineering/products-and-services/dotcom/apps/proxima/how-to-synchronize-apps-on-proxima/ for current best practices."
  end
end
