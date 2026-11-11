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
      AZURE_STORAGE_TOKEN_SCOPE = "https://storage.azure.com/.default"
      OIDC_CLIENT_ASSERTION_TYPE = "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

      sig { returns(T.nilable(::Azure::Storage::Common::Core::TokenCredential)) }; attr_reader :token_credential
      sig { returns(T.nilable(Time)) }; attr_reader :token_expires

      sig { void }
      def initialize
        @token_credential = T.let(nil, T.nilable(::Azure::Storage::Common::Core::TokenCredential))
        @token_expires = T.let(nil, T.nilable(Time))
      end

      # Returns true if Moda OIDC workload identity auth should be used instead
      # of client_secret-based auth. Requires the Azure Workload Identity webhook
      # to have injected AZURE_FEDERATED_TOKEN_FILE into the pod environment.
      sig { returns(T::Boolean) }
      def use_oidc_auth?
        FeatureFlag.vexi.enabled?("security_center_export_use_oidc_auth", default: false)
      end

      # Method to get OAuth token using either OIDC workload identity (preferred)
      # or legacy service credentials from ENV variables.
      sig { returns(::Azure::Storage::Common::Core::TokenCredential) }
      def get_oauth_token
        # If it's a new token or the token has expired, get a new token
        if @token_expires.nil? || @token_expires < Time.now
          if use_oidc_auth?
            acquire_token_via_oidc
          else
            acquire_token_via_client_secret
          end
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

      private

      # Acquires an Azure AD token via OIDC workload identity federation.
      # Reads the projected service account token from AZURE_FEDERATED_TOKEN_FILE
      # (injected by the workload identity webhook when the pod has the
      # azure.workload.identity/use label) and exchanges it for an Azure AD token.
      # Client ID and tenant ID come from application config (Vault), not from
      # webhook-injected env vars, so multiple services can share the same pod.
      sig { void }
      def acquire_token_via_oidc
        federated_token_file = ENV["AZURE_FEDERATED_TOKEN_FILE"]
        client_id = GitHub.security_center_export_azure_spn_client_id
        tenant_id = GitHub.security_center_export_azure_spn_tenant_id

        if federated_token_file.nil?
          raise StandardError, "AZURE_FEDERATED_TOKEN_FILE is not set. " \
            "Ensure the pod has the azure.workload.identity/use: 'true' label."
        end

        if client_id.blank? || tenant_id.blank?
          raise StandardError, "Azure SPN client_id or tenant_id is not configured. " \
            "Check security_center_export_azure_spn_client_id and tenant_id in Vault."
        end

        federated_token = File.read(federated_token_file).strip

        token_url = URI.parse("https://login.microsoftonline.com/#{tenant_id}/oauth2/v2.0/token")
        connection = GitHub::FaradayClient.external("SecurityCenterExportOIDC", token_url)

        response = connection.post do |req|
          req.headers["Content-Type"] = "application/x-www-form-urlencoded"
          req.body = URI.encode_www_form({
            grant_type: "client_credentials",
            client_id: client_id,
            client_assertion_type: OIDC_CLIENT_ASSERTION_TYPE,
            client_assertion: federated_token,
            scope: AZURE_STORAGE_TOKEN_SCOPE,
          })
        end

        unless response.status == 200
          raise StandardError, "Failed to acquire Azure AD token via OIDC: " \
            "status=#{response.status} body=#{response.body}"
        end

        response_body = GitHub::JSON.load(response.body)
        token = response_body["access_token"]
        expires_in = response_body["expires_in"].to_i

        @token_credential = ::Azure::Storage::Common::Core::TokenCredential.new(token)
        @token_expires = Time.now.utc + expires_in
      end

      # Legacy auth: acquires an Azure AD token via client_secret (client_credentials grant).
      sig { void }
      def acquire_token_via_client_secret
        tenant_id = GitHub.security_center_export_azure_spn_tenant_id
        client_id = GitHub.security_center_export_azure_spn_client_id
        client_secret = GitHub.security_center_export_azure_spn_client_secret

        azure_environment = GitHub::Azure::AzureEnvironmentSelector.get_environment
        token_provider_settings = GitHub::Azure::ActiveDirectoryServiceSettings.get_settings(azure_environment)
        token_provider_settings.token_audience = AZURE_STORAGE_TOKEN_AUDIENCE

        token_provider = GitHub::Azure::ApplicationTokenProvider.new(
          tenant_id,
          client_id,
          client_secret,
          token_provider_settings,
        )

        token_provider.get_authentication_header

        @token_credential = ::Azure::Storage::Common::Core::TokenCredential.new(token_provider.token)
        @token_expires = token_provider.token_expires_on
      end
    end
  end
end
