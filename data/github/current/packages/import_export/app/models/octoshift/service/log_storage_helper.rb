# typed: true
# frozen_string_literal: true

require "s3_sign"
require "azure/storage/blob"
require "azure/core/http/http_error"
require "github/azure_token_credential"

module Octoshift
  module Service
    class LogStorageHelper
      class UploadError < StandardError; end
      class GenerateUrlError < StandardError; end
      class MissingCredentialsError < StandardError; end

      AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"
      SIGNED_URL_EXPIRATION_TIME = 5.days
      LOGS_EXTENSION = "-logs.txt"

      def blob_name_for(org_name, log_name)
        "#{org_name}/#{log_name}#{LOGS_EXTENSION}"
      end

      def upload_repo_log(org_name, log_name, content)
        org_logs_path = Dir.mktmpdir(org_name)
        repository_key = blob_name_for(org_name, log_name)
        repository_log_file_path = File.join(org_logs_path, "#{log_name}#{LOGS_EXTENSION}")
        File.open(repository_log_file_path, "wb") do |file|
          file.write(content)
          file.close
          upload(repository_key, file, log_name)
        end
      ensure
        FileUtils.remove_entry(org_logs_path) if org_logs_path && File.exist?(org_logs_path)
      end

      def get_repo_log_url(org_name, log_name)
        if spn_authentication_enabled?
          get_repo_log_url_spn(org_name, log_name)
        else
          get_repo_log_url_memory_alpha(org_name, log_name)
        end
      end

      private

      def spn_authentication_enabled?
        return @spn_authentication_enabled if defined?(@spn_authentication_enabled)

        @spn_authentication_enabled = FeatureFlag.vexi.enabled?(:octoshift_spn_log_storage, default: false)
      end

      # ============================================
      # Memory Alpha implementation (legacy)
      # ============================================

      def get_repo_log_url_memory_alpha(org_name, log_name)
        repo_key = blob_name_for(org_name, log_name)
        memory_alpha_client.get_object({
          bucket: GitHub.octoshift_memory_alpha_bucket,
          key: repo_key
        })
        signed_url_for_memory_alpha(repo_key)
      rescue Aws::S3::Errors::NotFound, Aws::S3::Errors::ServiceError
        raise(GenerateUrlError, "Failed to generate url to download migration log for: #{log_name}")
      end

      # Returns an S3 client for Memory-Alpha for Octoshift's Azure container.
      # This account stores objects for internal services.
      def memory_alpha_client
        @memory_alpha_client ||= Aws::S3::Client.new({
          endpoint: GitHub.memory_alpha_url,
          force_path_style: true,
          access_key_id: GitHub.octoshift_memory_alpha_key_id,
          secret_access_key: GitHub.octoshift_memory_alpha_access_key,
          region: "us-west-2"
        })
      end

      # Uploads content to a designated path (key) using Memory Alpha.
      def upload(key, content, log_name)
        if spn_authentication_enabled?
          upload_spn(key, content, log_name)
        else
          upload_memory_alpha(key, content, log_name)
        end
      end

      def upload_memory_alpha(key, content, log_name)
        memory_alpha_client.put_object(
          body: content,
          bucket: GitHub.octoshift_memory_alpha_bucket,
          key: key,
        )
      rescue Aws::S3::Errors::ServiceError
        raise(UploadError, "Failed to upload migration log for: #{log_name}")
      rescue Aws::Sigv4::Errors::MissingCredentialsError
        raise(MissingCredentialsError, "Could not connect to Azure: Missing Credentials. Could not upload logs for: #{log_name}")
      end

      # Uploads and returns a signed url for an uploaded object.
      def signed_url_for_memory_alpha(key)
        s3_credentials = {
          bucket: GitHub.octoshift_memory_alpha_bucket,
          key: GitHub.octoshift_memory_alpha_key_id,
          secret: GitHub.octoshift_memory_alpha_access_key,
        }

        MemoryAlphaSign.query(s3_credentials, "GET", key, SIGNED_URL_EXPIRATION_TIME).location
      end

      # ============================================
      # SPN/Azure Blob Storage implementation (new)
      # ============================================

      def get_repo_log_url_spn(org_name, log_name)
        blob_name = blob_name_for(org_name, log_name)

        # Verify the blob exists
        azure_blob_client.get_blob_metadata(storage_container_name, blob_name)
        signed_url_for_spn(blob_name, log_name)
      rescue ::Azure::Core::Http::HTTPError => e
        if e.status_code == 404
          raise(GenerateUrlError, "Failed to generate url to download migration log for: #{log_name}")
        else
          raise(GenerateUrlError, "Failed to generate url to download migration log for: #{log_name}: #{e.message}")
        end
      end

      # Returns an Azure Blob Service client for Memory-Alpha for Octoshift's Azure container.
      # This account stores objects for internal services using SPN authentication.
      # Uses GitHub::AzureTokenCredential to automatically refresh tokens when they expire.
      def azure_blob_client
        @azure_blob_client ||= begin
          azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
          token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
          token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE

          token_provider = GitHub::Azure::ApplicationTokenProvider.new(
            GitHub.spn_memory_alpha_tenant_id,
            GitHub.spn_memory_alpha_client_id,
            GitHub.spn_memory_alpha_client_secret,
            token_provider_settings
          )

          token_credential = GitHub::AzureTokenCredential.new(token_provider)
          token_signer = ::Azure::Storage::Common::Core::Auth::TokenSigner.new(token_credential)

          ::Azure::Storage::Blob::BlobService.create({
            storage_account_name: storage_account_name,
            signer: token_signer
          })
        end
      end

      # Storage account name for Azure Blob Storage
      def storage_account_name
        # Use the same key_id that previously held the storage account name
        GitHub.octoshift_memory_alpha_key_id
      end

      # Container name (equivalent to S3 bucket)
      def storage_container_name
        GitHub.octoshift_memory_alpha_bucket
      end

      # Uploads content to Azure Blob Storage using SPN authentication.
      def upload_spn(blob_name, content, log_name)
        azure_blob_client.create_block_blob(
          storage_container_name,
          blob_name,
          content
        )
      rescue ::Azure::Core::Http::HTTPError => e
        if e.status_code == 401 || e.status_code == 403
          raise(MissingCredentialsError, "Could not connect to Azure: Missing Credentials. Could not upload logs for: #{log_name}")
        else
          raise(UploadError, "Failed to upload migration log for: #{log_name}: #{e.message}")
        end
      end

      # Generates and returns a signed SAS URL for an uploaded blob.
      def signed_url_for_spn(blob_name, log_name)
        expiry = Time.current.utc + SIGNED_URL_EXPIRATION_TIME

        # Get user delegation key for SAS token generation
        start_time = Time.current.utc
        user_delegation_key = azure_blob_client.get_user_delegation_key(start_time, expiry)

        # Generate SAS token using user delegation key
        sas_generator = ::Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(
          storage_account_name,
          "", # account key not used with user delegation key
          user_delegation_key
        )

        sas_options = {
          resource: "b",          # blob
          protocol: "https",
          permissions: "r",       # read-only
          expiry: expiry.to_s
        }

        sas_token = sas_generator.generate_service_sas_token(
          "#{storage_container_name}/#{blob_name}",
          sas_options
        )

        "https://#{storage_account_name}.blob.core.windows.net/#{storage_container_name}/#{blob_name}?#{sas_token}"
      rescue ::Azure::Core::Http::HTTPError, StandardError => e
        raise(GenerateUrlError, "Failed to generate url to download migration log for: #{log_name}: #{e.message}")
      end
    end
  end
end
