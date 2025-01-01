# typed: true
# frozen_string_literal: true

# Description: Allow transfer of files to a customer's Azure Blob Storage service
require "azure/storage/common"
require "azure/storage/common/client_options_error"
require "azure/storage/blob"
require "azure/core/http/http_error"

module GitHub
  class Migrator
    class MigrationFileUploader
      AZURE_BLOCK_SIZE = 4194304

      attr_reader :migration_file, :archive_path, :storage_policy

      def initialize(migration_file:, archive_path:, storage_policy:)
        @migration_file = migration_file
        @archive_path = archive_path
        @storage_policy = storage_policy
      end

      def call
        return upload_azure if should_upload_azure?
        return upload_s3 if should_upload_s3?
        upload_local
      end

      private

      def should_upload_s3?
        storage_policy.class == ::Storage::S3Policy || GitHub.enterprise? && GitHub.migrations_blob_storage_type == "s3"
      end

      def should_upload_azure?
        storage_policy.class == ::Storage::AzurePolicy || GitHub.enterprise? && GitHub.migrations_blob_storage_type == "azure"
      end

      def upload_local
        File.open(archive_path, "rb") do |tarball|
          storage_policy.upload_contents!(tarball)
        end
        true
      end

      def upload_s3
        s3_key = migration_file.storage_s3_key(storage_policy)
        s3_object = aws_s3_object(s3_key)

        begin
          s3_object.upload_file(archive_path,
            multipart_threshold: max_archive_size,
            acl: acl,
          )
        rescue Aws::S3::MultipartUploadError => error
          raise GitHub::Migrator::MultipartUploadError, "Error during multipart upload for "\
            "#{migration_file.class} ##{migration_file.id}: #{error.message}"
        end
      end

      def aws_s3_resource
        Aws::S3::Resource.new(client: migration_file.storage_client)
      end

      def aws_s3_bucket
        aws_s3_resource.bucket(migration_file.storage_s3_bucket)
      end

      def aws_s3_object(key)
        aws_s3_bucket.object(key)
      end

      def upload_azure
        # The Azure Storage SDK we use only allows the proxy to be configured using the HTTP_PROXY or
        # HTTPS_PROXY environment variables. These aren't set when a customer is using Azure Blob Storage
        # for their migration storage in GHES, so we need to set them temporarily.
        with_http_proxy_environment_variable_if_proxy_configured do
          # Upload to Azure Blob Storage for GHES exports
          # For now default to chunked upload
          begin
            migration_file.storage_client.upload_to_blob_chunked(archive_path, migration_file.name)
          rescue GitHub::AzureSnapshotUploader::UploadError => error
            raise GitHub::Migrator::MultipartUploadError, "Error during multipart upload for "\
              "#{migration_file.class} ##{migration_file.id}: #{error.message}"
          end
        end
      end

      def upload_snapshot_to_azure
        begin
          migration_file.storage_client.upload_to_blob(archive_path, migration_file.name)
        rescue GitHub::AzureSnapshotUploader::UploadError => error
          raise GitHub::Migrator::MultipartUploadError, "Error during multipart upload for "\
            "#{migration_file.class} ##{migration_file.id}: #{error.message}"
        end
      end

      def acl
        storage_policy.acl
      end

      def max_archive_size
        ::Storage::Uploadable::MAX_ASSET_SIZE
      end

      # Private: Configures a client for interacting with Azure Blob service
      #
      # Returns ::Azure::Storage::Blob::BlobService
      def azure_blob_client
        return @azure_blob_client if defined?(@azure_blob_client)
        @azure_blob_client = ::Azure::Storage::Blob::BlobService.create_from_connection_string(GitHub.migrations_azure_connection_string)
      end

      def with_http_proxy_environment_variable_if_proxy_configured(&block)
        if GitHub.enterprise? && GitHub.http_proxy_config.present?
          with_temporary_env("HTTP_PROXY", GitHub.http_proxy_config, &block)
        else
          block.call
        end
      end

      def with_temporary_env(key, value, &block)
        env_value_before = ENV[key]
        ENV[key] = value

        begin
          block.call
        ensure
          ENV[key] = env_value_before
        end
      end
    end
  end
end
