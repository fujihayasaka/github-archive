# typed: true
# frozen_string_literal: true

require "test_helper"

module Billing::PackageRegistry
  class DataTransferLineItemCreatorTest < GitHub::TestCase
    include HydroTestHelpers

    fixtures do
      @owner = create(:user)
      @actor = create(:user)
      @repo = create(:repository, owner: @owner, from_example: :repository_test_simple)
      @package = create(:registry_package, repository: @repo)
      @package_version = create(:registry_package_version, package: @package)
      @source_uri = "gid://GitHub/StreamProcessor/package_version_downloaded_processor/event_id/6ba86fa6-490a-4180-ba03-24d4771ff66e"

    end

    test "sends usage to Meuse" do
      size_in_bytes = 1.megabyte
      downloaded_at = Time.parse("2018-12-09 18:10:07.000")
      name = "package_name"

      ::Billing::PackageRegistry::DataTransferLineItemCreator.create(
        owner: @owner,
        actor_id: @actor.id,
        registry_package_id: @package.id,
        registry_package_version_id: @package_version.id,
        name: name,
        size_in_bytes: size_in_bytes,
        download_id: "95af4e6c-72d5-11ed-a1eb-0242ac120002",
        downloaded_at: downloaded_at,
        source_uri: @source_uri
      )

      assert_hydro_published({
        product_name: "packages",
        product_sku_name: "default",
        quantity: size_in_bytes,
        account_id: @owner.id,
        actor_id: { value: @actor.id },
        usage_at: Google::Protobuf::Timestamp.new(seconds: downloaded_at.to_i),
        usage_uuid: "c4dc7800-43cd-32aa-b4c0-06f64edd17f4",
        source_uri: @source_uri,
        custom_fields: {
          "package.download.id": "95af4e6c-72d5-11ed-a1eb-0242ac120002",
          "package.id": @package.id.to_s,
          "package.name": name,
          "package.version.id": @package_version.id.to_s,
        }
      }, schema: "meuse.v0.MeteredUsage")
    end

    test "does not send usage to Meuse if the size is zero" do
      size_in_bytes = 0
      download_id = SecureRandom.uuid
      downloaded_at = Time.parse("2018-12-09 18:10:07.000")
      name = "package_name"

      ::Billing::PackageRegistry::DataTransferLineItemCreator.create(
        owner: @owner,
        actor_id: @actor.id,
        registry_package_id: @package.id,
        registry_package_version_id: @package_version.id,
        name: name,
        size_in_bytes: size_in_bytes,
        download_id: download_id,
        downloaded_at: downloaded_at,
        source_uri: @source_uri
      )

      refute_hydro_messages(schema: "meuse.v0.MeteredUsage")
    end
  end
end if GitHub.billing_enabled?
