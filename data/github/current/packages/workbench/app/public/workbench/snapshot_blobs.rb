# typed: strict
# frozen_string_literal: true

module Workbench
  class SnapshotBlobs
    @azure_storage_client = T.let(Workbench::AzureStorageClient.new, Workbench::AzureStorageClient)

    sig do
      params(
      container_name: String,
      current_user: T.nilable(::User),
      readonly: T::Boolean,
      expiry_minutes: Integer
      ).returns(T.nilable(String))
    end
    def self.get_snapshot_upload_uri(container_name, current_user: nil, readonly: false, expiry_minutes: 60)
      return if Rails.env.development?

      permissions = readonly ? "rl" : "rwdl" # Read + List | Read + Write + Delete + List - needs to be in that order watch out.

      generate_user_delegation_sas_uri(container_name, permissions, expiry_minutes)
    end

    sig { params(container_name: String).void }
    def self.create_container_if_not_exists(container_name)
      return if Rails.env.development?

      begin
        get_blob_client.create_container(container_name)
      rescue Azure::Core::Http::HTTPError => e
        # Container already exists (409 Conflict) is expected, just return
        raise unless e.status_code == 409
      end
    end

    sig { returns(Azure::Storage::Blob::BlobService) }
    def self.get_blob_client
      azure_storage_client.get_client(storage_account_name: GitHub.copilot_workbench_snapshot_storage_account)
    end

    sig { params(container_name: String, permissions: String, expiry_minutes: Integer).returns(String) }
    def self.generate_user_delegation_sas_uri(container_name, permissions, expiry_minutes)
      storage_account_name = GitHub.copilot_workbench_snapshot_storage_account

      azure_storage_client.generate_user_delegation_sas_uri(
        container_name: container_name,
        permissions: permissions,
        expiry_minutes: expiry_minutes,
        storage_account_name: storage_account_name
      )
    end

    sig { returns(Workbench::AzureStorageClient) }
    def self.azure_storage_client
      @azure_storage_client
    end

    private_class_method :get_blob_client, :generate_user_delegation_sas_uri, :azure_storage_client
  end
end
