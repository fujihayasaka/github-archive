# typed: true
# frozen_string_literal: true

require "proto-registry-metadata-migrator-api"

module PackageRegistry
  module Twirp
    class MigratorClient < PackageRegistry::Twirp::BaseClient
      def initialize
        # NOTE: This uses the same HMAC key as the metadata client to keep the existing behaviour.
        # RMS does allow using separate HMAC keys for the metadata and migrator API.
        # It's not actually clear if the migrator API is correctly setup in production.
        # To mitigate the risk of breaking the metadata API, we're keep using the same HMAC key.
        super(package_registry_hmac_key: GitHub.package_registry_metadata_hmac_key)
      end

      def rpc(method, params)

        begin
          response = client.rpc(method, params)
        rescue Faraday::TimeoutError => error
          failbot_report(error)
          raise PackageRegistry::Twirp::Error, "PackageRegistry request timed out."
        rescue Faraday::ConnectionFailed => error
          failbot_report(error)
          raise PackageRegistry::Twirp::ServiceUnavailableError, "PackageRegistry could not connect."
        end

        if response.error.code == :unavailable
          handle_twirp_error(response.error, error_class: PackageRegistry::Twirp::ServiceUnavailableError)
        end

        response
      end

      def does_name_conflict?(namespace:, package_name:, ecosystem:)

        response = client.rpc(:DoesNameConflict,
          namespace: namespace,
          package_name: package_name,
          ecosystem: ecosystem_to_proto(ecosystem)
        )

        return false if response.error.blank?

        return true if response.error.code == :already_exists

        handle_twirp_error(response.error)
      end

      def emit_migration_download_event?(namespace:, package_name:, version_name:, ecosystem: :container)

        response = client.rpc(:EmitDownloadEvent,
          namespace: namespace,
          package_name: package_name,
          version_name: version_name,
          ecosystem: ecosystem_to_proto(ecosystem)
        )

        return response if response.error.blank?
        handle_twirp_error(response.error)
      end

      def sync_download_count?(namespace:, package_name:, version_name:, ecosystem: :npm)

        response = client.rpc(:SyncDownloadCount,
          namespace: namespace,
          package_name: package_name,
          version_name: version_name,
          ecosystem: ecosystem_to_proto(ecosystem)
        )

        return response if response.error.blank?
        handle_twirp_error(response.error)
      end

      private

      def twirp_class
        Proto::RegistryMetadata::V1::Migrator::MigratorClient
      end

      def ecosystem_to_proto(ecosystem)
        {
          container: Proto::RegistryMetadata::V1::Package::Ecosystem::CONTAINER,
          npm: Proto::RegistryMetadata::V1::Package::Ecosystem::NPM,
          nuget: Proto::RegistryMetadata::V1::Package::Ecosystem::NUGET,
          rubygems: Proto::RegistryMetadata::V1::Package::Ecosystem::RUBYGEMS
        }
        .fetch(ecosystem&.downcase.to_sym, Proto::RegistryMetadata::V1::Package::Ecosystem::UNKNOWN)
      end
    end
  end
end
