# typed: strict
# frozen_string_literal: true

module Workbench
  ##
  ## An Azure Blob Storage client for the Workbench's Eyesite scanning feature.
  ##
  class ScanningBlobClient

    @azure_storage_client = T.let(Workbench::AzureStorageClient.new, Workbench::AzureStorageClient)

    sig { params(app: String, deployment_id: T.nilable(String), data: T.any(String, IO)).void }
    def self.upload(app, deployment_id, data)
      asset_name = "#{app}/#{deployment_id || 'default'}"

      blob_service_client.create_block_blob(container_name, asset_name, data)

      nil
    end

    sig { params(runtime_app_deploy: ::Spark::RuntimeAppDeploy, expires_in_minutes: Integer).returns(String) }
    def self.get_signed_url(runtime_app_deploy, expires_in_minutes)
      app = T.must(runtime_app_deploy.runtime_app).permanent_name
      deployment_id = runtime_app_deploy.id
      asset_name = "#{app}/#{deployment_id}"

      permissions = "r" # Read

      generate_user_delegation_sas_url(asset_name, permissions, expires_in_minutes)
    end

    sig { returns(String) }
    def self.storage_account_name
      GitHub.copilot_workbench_scanning_storage_account
    end

    sig { returns(Azure::Storage::Blob::BlobService) }
    def self.blob_service_client
      client = azure_storage_client.get_client(storage_account_name: self.storage_account_name)
      create_container_if_not_exists(client)
      client
    end

    sig { returns(String) }
    def self.container_name
      "uploads"
    end

    sig { params(blob_service: Azure::Storage::Blob::BlobService).void }
    def self.create_container_if_not_exists(blob_service)
      begin
        blob_service.create_container(container_name)
      rescue Azure::Core::Http::HTTPError => e
        raise unless e.status_code == 409
      end
    end

    sig { params(asset_name: String, permissions: String, expires_in_minutes: Integer).returns(String) }
    def self.generate_user_delegation_sas_url(asset_name, permissions, expires_in_minutes)
      azure_storage_client.generate_user_delegation_sas_uri(
        container_name: container_name,
        blob_name: asset_name,
        permissions: permissions,
        expiry_minutes: expires_in_minutes,
        storage_account_name: storage_account_name
      )
    end

    sig { returns(Workbench::AzureStorageClient) }
    def self.azure_storage_client
      @azure_storage_client
    end

    private_class_method :blob_service_client, :create_container_if_not_exists, :container_name, :storage_account_name, :generate_user_delegation_sas_url, :azure_storage_client
  end
end
