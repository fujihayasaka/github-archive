# typed: true
# frozen_string_literal: true

# Description: Allow transfer of files to a customer's Azure Blob Storage service
require "azure/storage/common"
require "azure/storage/common/client_options_error"
require "azure/storage/blob"
require "azure/core/http/http_error"

module GitHub
  class AzureSnapshotUploader
    AZURE_BLOCK_SIZE = T.let(4.megabytes, Integer)

    class UploadError < StandardError; end

    def initialize(container_name: "", storage_account_name: nil, storage_access_key: nil, storage_connection_string: nil, use_connection_string: false)
      @container_name = container_name

      if use_connection_string
        raise ArgumentError, "storage_connection_string cannot be blank" if storage_connection_string.blank?

        @storage_connection_string = storage_connection_string
      else
        raise ArgumentError, "storage_account_name cannot be blank" if storage_account_name.blank?
        raise ArgumentError, "storage_access_key cannot be blank" if storage_access_key.blank?

        @storage_account_name = storage_account_name
        @storage_access_key = storage_access_key
      end
    end

    # Public: Uploads the repo snapshot file to the enterprise's Azure Blob Service
    #
    # Returns Boolean or raises UploadError
    def upload_to_blob(snapshot_location, filename)
      snapshot_blob = ::File.open(snapshot_location, "rb") { |file| file.read }
      azure_blob_client.create_block_blob(
        @container_name,
        filename,
        snapshot_blob,
        options: {}
      )
      true
    rescue ::Azure::Core::Http::HTTPError => error
      raise UploadError.new(error.message)
    rescue ::Azure::Storage::Common::InvalidOptionsError => e
      raise UploadError.new("Azure configuration invalid")
    end

    # Public: Uploads file to Azure Blob Service in chunks
    #
    # Returns Boolean or raises UploadError
    def upload_to_blob_chunked(file_path, filename)
      # Create or Get container to upload
      begin
        container = azure_blob_client.create_container(@container_name)
      rescue ::Azure::Core::Http::HTTPError => error
        raise error unless error.message.include?("The specified container already exists.")
        container = azure_blob_client.get_container_metadata(@container_name)
      end

      acl = azure_blob_client.get_container_acl(@container_name)
      raise UploadError.new("Azure configuration invalid: ACL policy is set to public. Please ensure the `migration-archives` container has private ACL") if acl.first.instance_of?(::Azure::Storage::Blob::Container::Container) && acl.first.public_access_level == "container"

      # Upload blob in chunks
      blocks = []
      block_count = 0

      # Read the file
      File.open file_path, "rb" do |file|
        while (file_bytes = file.read(AZURE_BLOCK_SIZE))
          block_id = Base64.strict_encode64(SecureRandom.uuid)
          azure_blob_client.put_blob_block(
            @container_name,
            filename,
            block_id,
            file_bytes
          )

          blocks << [block_id]
          block_count += 1
        end
      end

      # Commit the blob blocks to assemble file
      azure_blob_client.commit_blob_blocks(@container_name, filename, blocks)
    rescue ::Azure::Core::Http::HTTPError => error
      raise UploadError.new(error.message)
    rescue ::Azure::Storage::Common::InvalidOptionsError => e
      raise UploadError.new("Azure configuration invalid")
    end

    def generate_sas_url(filename)
      storage_path = File.join(@container_name, filename)
      expiry = Time.now.utc + 48.hours
      sas_token = azure_storage_signer.generate_service_sas_token(storage_path, { service: "b", resource: "b", protocol: "https", permissions: "r", expiry: expiry.to_s })
      uri = Addressable::URI.parse(azure_blob_client.client.storage_blob_host)
      uri.path = storage_path
      uri.query = sas_token
      uri.to_s
    end

    private

    # Private: Configures a client for interacting with Azure Blob service
    #
    # Returns ::Azure::Storage::Blob::BlobService
    def azure_blob_client
      @azure_blob_client ||= begin
        if @storage_connection_string.present?
          @azure_blob_client = ::Azure::Storage::Blob::BlobService.create_from_connection_string(@storage_connection_string)
        else
          @azure_blob_client = ::Azure::Storage::Blob::BlobService.create(storage_account_name: @storage_account_name, storage_access_key: @storage_access_key)
        end
      end
    end

    def azure_storage_signer
      @azure_storage_signer ||= ::Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(azure_blob_client.client.storage_account_name, azure_blob_client.client.storage_access_key)
    end
  end
end
