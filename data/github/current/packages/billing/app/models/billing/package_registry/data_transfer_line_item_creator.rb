# typed: strict
# frozen_string_literal: true

module Billing
  module PackageRegistry
    class DataTransferLineItemCreator

      sig do
        params(
          owner: ::Billing::Types::Account,
          actor_id: T.nilable(Integer),
          registry_package_id: T.any(String, Integer),
          registry_package_version_id: T.any(String, Integer),
          name: T.nilable(String),
          size_in_bytes: ::Billing::Types::Numeric,
          download_id: String,
          downloaded_at: Time,
          source_uri: String,
        ).void
      end
      def self.create(owner:, actor_id:, registry_package_id:, registry_package_version_id:, name:, size_in_bytes:, download_id:, downloaded_at:, source_uri:)
        new.create(owner: owner, actor_id: actor_id, registry_package_id: registry_package_id, registry_package_version_id: registry_package_version_id, name: name, size_in_bytes: size_in_bytes, download_id: download_id, downloaded_at: downloaded_at, source_uri: source_uri)
      end

      sig do
        params(
          owner: ::Billing::Types::Account,
          actor_id: T.nilable(Integer),
          registry_package_id: T.any(String, Integer),
          registry_package_version_id: T.any(String, Integer),
          name: T.nilable(String),
          size_in_bytes: ::Billing::Types::Numeric,
          download_id: String,
          downloaded_at: Time,
          source_uri: String,
        ).void
      end
      def create(owner:, actor_id:, registry_package_id:, registry_package_version_id:, name:, size_in_bytes:, download_id:, downloaded_at:, source_uri:)

        if size_in_bytes.positive?

          custom_fields = {
            "package.id" => registry_package_id,
            "package.version.id" => registry_package_version_id,
            "package.name" => name,
            "package.download.id" => download_id,
          }

          payload = {
            product_name: "packages",
            product_sku_name: "default",
            quantity: size_in_bytes,
            account_id: owner.id,
            actor_id: actor_id,
            usage_at: downloaded_at,
            usage_uuid: GitHub::Billing::MeteredProduct.usage_uuid("Packages/#{download_id}"),
            source_uri: source_uri,
            custom_fields: custom_fields,
          }

          GlobalInstrumenter.instrument("meuse.metered_usage", payload)
        end
      end

    end
  end
end
