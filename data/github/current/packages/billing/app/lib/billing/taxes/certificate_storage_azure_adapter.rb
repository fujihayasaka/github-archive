# typed: strict
# frozen_string_literal: true

module Billing
  module Taxes
    class CertificateStorageAzureAdapter
      include Billing::Interfaces::RemoteFileStorage

      TAX_CERTIFICATES_AZURE_BLOB_CONTAINER = T.let("tax-exemption-certs", String)
      CONTENT_TYPES = T.let({
        pdf: "application/pdf",
        png: "image/png",
        jpg: "image/jpeg",
        jpeg: "image/jpeg"
      }, T::Hash[Symbol, String])

      sig { override.params(file_name: String, file: String, options: T::Hash[Symbol, T.untyped]).returns(T::Boolean) }
      def upload(file_name:, file:, options:)
        uploaded_blob = azure_blob_client.upload(TAX_CERTIFICATES_AZURE_BLOB_CONTAINER, file_name, file, options: options)
        if uploaded_blob.present? && uploaded_blob.metadata.blank?
          azure_blob_client.set_blob_metadata(TAX_CERTIFICATES_AZURE_BLOB_CONTAINER, file_name, options[:metadata])
        end

        uploaded_blob.present?
      end

      sig { override.params(file_name: String).returns(String) }
      def download(file_name:)
        url = get_url(file_name: file_name, expires_in: 1.hour)

        Net::HTTP.get(URI.parse(url))
      end

      sig { override.params(file_name: String, expires_in: ActiveSupport::Duration).returns(String) }
      def get_url(file_name:, expires_in: 1.week)
        Billing::Azure::SharedAccessSignatureUrlGenerator.generate_sas_url(
          storage_config: Billing::Azure::Storage.account_management_config,
          blob_container: TAX_CERTIFICATES_AZURE_BLOB_CONTAINER,
          file_name: file_name,
          expires_in: expires_in,
          content_type: get_content_type(file_name)
        )
      end

      sig { override.params(file_name: String).returns(T::Boolean) }
      def delete(file_name:)
        azure_blob_client.delete_blob(TAX_CERTIFICATES_AZURE_BLOB_CONTAINER, file_name)
      end

      private

      sig { params(file_name: String).returns(String) }
      def get_content_type(file_name)
        ext = File.extname(file_name).delete_prefix(".")

        CONTENT_TYPES.fetch(ext.to_sym) { "application/octet-stream" }
      end

      sig { returns(Billing::Azure::BlobClient) }
      def azure_blob_client
        @azure_blob_client ||= T.let(Billing::Azure::BlobClient.new(Billing::Azure::Storage.account_management_config), T.nilable(Billing::Azure::BlobClient))
      end
    end
  end
end
