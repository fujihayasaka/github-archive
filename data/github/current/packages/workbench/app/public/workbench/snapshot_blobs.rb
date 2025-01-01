# typed: strict
# frozen_string_literal: true

module Workbench
  class SnapshotBlobs


    sig { params(container_name: String).returns(T.nilable(String)) }
    def self.get_snapshot_upload_uri(container_name)
      return if Rails.env.development?

      sas_token = Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(
        GitHub.copilot_workbench_snapshot_storage_account,
        GitHub.copilot_workbench_snapshot_access_key
      ).generate_service_sas_token(
        container_name,
        service: "b", # Blob service
        resource: "c", # Container
        permissions: "rwl", # Write + Read + List
        start: Time.now.utc.iso8601,
        expiry: 1.hour.from_now.utc.iso8601,
      )
      "#{get_blob_client.generate_uri(container_name)}?#{sas_token}"
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
      storage_account_name = GitHub.copilot_workbench_snapshot_storage_account
      storage_access_key = GitHub.copilot_workbench_snapshot_access_key
      common_client = Azure::Storage::Common::Client.create(
        storage_account_name: storage_account_name,
        storage_access_key: storage_access_key
      )

      Azure::Storage::Blob::BlobService.new(client: common_client)
    end

    private_class_method :get_blob_client

  end
end
