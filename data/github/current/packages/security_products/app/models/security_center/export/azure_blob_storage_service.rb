# typed: strict
# frozen_string_literal: true

require "github/security_center/logging_helper"

module SecurityCenter
  module Export
    class AzureBlobStorageService
      include BlobStorageService
      include GitHub::SecurityCenter::LoggingHelper
      include GitHub::Memoizer

      AZURE_STORAGE_TOKEN_AUDIENCE = "https://storage.azure.com/"

      sig { returns(T.nilable(::Azure::Storage::Common::Core::TokenCredential)) }; attr_reader :token_credential
      sig { returns(T.nilable(Time)) }; attr_reader :token_expires

      sig { void }
      def initialize
        @token_credential = T.let(nil, T.nilable(::Azure::Storage::Common::Core::TokenCredential))
        @token_expires = T.let(nil, T.nilable(Time))
      end

      # Method to get OAuth token using service credentials from ENV variables
      sig { returns(::Azure::Storage::Common::Core::TokenCredential) }
      def get_oauth_token
        # If it's a new token or the token has expired, get a new token
        if @token_expires.nil? || @token_expires < Time.now
          tenant_id = GitHub.security_center_export_azure_spn_tenant_id
          client_id = GitHub.security_center_export_azure_spn_client_id
          client_secret = GitHub.security_center_export_azure_spn_client_secret
          storage_account_name = GitHub.security_center_export_azure_storage_account_name

          azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_azure_environment
          token_provider_settings = MsRestAzure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
          token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE

          token_provider = MsRestAzure::ApplicationTokenProvider.new(
            tenant_id,
            client_id,
            client_secret,
            token_provider_settings,
          )

          token_provider.get_authentication_header

          @token_credential = ::Azure::Storage::Common::Core::TokenCredential.new(token_provider.token)
          @token_expires = token_provider.token_expires_on
        end

        T.must(@token_credential)
      end

      sig { override.params(key: String).void }
      def create(key)
        client.create_append_blob(GitHub.security_center_export_azure_blob_container, "security-center-#{key}.csv", options: { content_type: "text/csv" })
      end

      sig { override.params(key: String, value: String, feature: String).void }
      def store(key, value, feature)
        GitHub.dogstats.distribution("security_center.export.uncompressed_file_size", value.bytesize, tags: ["feature:#{feature}", "storage_service:azure"])

        begin
          client.append_blob_block(GitHub.security_center_export_azure_blob_container, "security-center-#{key}.csv", value, options: { content_type: "text/csv" })
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
          signer: Azure::Storage::Common::Core::Auth::TokenSigner.new(get_oauth_token)
        })
      end

      # Method to get User Delegation Key for a specific BlobService client
      sig { params(expiry: ActiveSupport::Duration).returns(Azure::Storage::Common::Service::UserDelegationKey) }
      def user_delegation_key(expiry = DEFAULT_EXPIRY)
        start_time = Time.now.utc
        # We need to make sure that the key is valid for the duration of the SAS token that we generate
        expiry_time = start_time + 5.minutes.to_i
        client.get_user_delegation_key(start_time, expiry_time)
      end

      sig { returns(::Azure::Storage::Common::Core::Auth::SharedAccessSignature) }
      memoize def azure_storage_signer
        ::Azure::Storage::Common::Core::Auth::SharedAccessSignature.new(GitHub.security_center_export_azure_storage_account_name, "", user_delegation_key)
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
