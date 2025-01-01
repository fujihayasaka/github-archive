# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module Export
    class AzureBlobStorageService
      extend T::Sig
      include BlobStorageService
      include GitHub::SecurityCenter::LoggingHelper
      include GitHub::Memoizer

      sig { override.params(key: String, use_append_blob: T::Boolean).void }
      def create(key, use_append_blob = false)
        if use_append_blob
          client.create_append_blob(GitHub.security_center_export_azure_blob_container, "security-center-#{key}.csv", options: { content_type: "text/csv" })
        end
      end

      sig { override.params(key: String, value: String, feature: String, use_append_blob: T::Boolean).void }
      def store(key, value, feature, use_append_blob = false)
        GitHub.dogstats.distribution("security_center.export.uncompressed_file_size", value.bytesize, tags: ["feature:#{feature}", "storage_service:azure"])

        begin
          if use_append_blob
            client.append_blob_block(GitHub.security_center_export_azure_blob_container, "security-center-#{key}.csv", value, options: { content_type: "text/csv" })
          else
            client.create_block_blob(GitHub.security_center_export_azure_blob_container, "security-center-#{key}.csv", value, options: { content_type: "text/csv" })
          end
        rescue ::Azure::Core::Http::HTTPError => error
          GitHub.dogstats.increment(
            "security_center.export.upload",
            tags: ["success:false", "status:#{error.status_code}}", "error:#{error.type}", "feature:#{feature}", "storage_service:azure"]
          )
          raise error
        end
      end

      sig { override.params(key: String, feature: String, filename: String, expiry: ActiveSupport::Duration).returns(T.nilable(BlobServiceResponse)) }
      def retrieve(key, feature, filename = "", expiry = DEFAULT_EXPIRY)
        azure_blob = begin
          azure_file_name = "security-center-#{key}.csv"
          blob_url = generate_sas_url(azure_file_name, filename, expiry)
          blob_size = client.get_blob_properties(GitHub.security_center_export_azure_blob_container, azure_file_name).properties[:content_length]
          BlobServiceResponse.new(
            blob_url:,
            blob_size:,
          )
        rescue ::Azure::Core::Http::HTTPError => error
          GitHub.dogstats.increment(
            "security_center.export.get_blob",
            tags: ["success:false", "status:#{error.status_code}}", "error:#{error.type}", "feature:#{feature}", "storage_service:azure"]
          )
          raise error
        end
      end

      sig { returns(::Azure::Storage::Blob::BlobService) }
      memoize def client
        ::Azure::Storage::Blob::BlobService.create({
          storage_account_name: GitHub.security_center_export_azure_storage_account_name,
          storage_access_key: GitHub.security_center_export_azure_storage_access_key,
        })
      end

      sig { returns(::Azure::Storage::Common::Core::Auth::SharedAccessSignature) }
      memoize def azure_storage_signer
        ::Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(client.client.storage_account_name, client.client.storage_access_key)
      end

      sig { params(key: String, filename: String, expiry: ActiveSupport::Duration).returns(String) }
      def generate_sas_url(key, filename, expiry = DEFAULT_EXPIRY)
        storage_path = File.join(GitHub.security_center_export_azure_blob_container, key)
        expiry = Time.now.utc + expiry.to_i
        sas_token = azure_storage_signer.generate_service_sas_token(storage_path, {
          service: "b", # blob service
          resource: "b", # getting a blob
          protocol: "https",
          permissions: "r", # read-only
          expiry: expiry.to_s,
          content_disposition: "attachment; filename=\"#{filename}\""
        })
        uri = Addressable::URI.parse(client.client.storage_blob_host)
        uri.path = storage_path
        uri.query = sas_token
        uri.to_s
      end
    end
  end
end
