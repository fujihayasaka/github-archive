# typed: strict
# frozen_string_literal: true

##
## An Azure Blob Storage client for the Workbench's Eyesite scanning feature.
##
module Workbench
  class ScanningBlobClient

    sig { params(app: String, deployment_id: T.nilable(String), data: T.any(String, IO)).returns(String) }
    def self.upload(app, deployment_id, data)
      blob_service = container_client
      asset_name = "#{app}/#{deployment_id || 'default'}"

      blob_service.create_block_blob(container_name, asset_name, data)

      "#{storage_account_name}/#{container_name}/#{asset_name}"
    end

    sig { returns(String) }
    def self.storage_account_name
      GitHub.copilot_workbench_scanning_storage_account
    end

    sig { returns(Azure::Storage::Blob::BlobService) }
    def self.container_client
      storage_access_key = GitHub.copilot_workbench_scanning_access_key

      common_client = Azure::Storage::Common::Client.create(
        storage_account_name: storage_account_name,
        storage_access_key: storage_access_key
      )

      blob_service = Azure::Storage::Blob::BlobService.new(client: common_client)
      create_container_if_not_exists(blob_service)

      blob_service
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

    private_class_method :container_client, :create_container_if_not_exists, :container_name, :storage_account_name
  end
end
