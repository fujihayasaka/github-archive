# typed: true
# frozen_string_literal: true

require "test_helper"
require "azure/storage/common"
require "azure/storage/blob"
require "azure/core/http/http_error"
require "azure/core/http/http_response"
require "ms_rest_azure"
require "github/azure/ms_rest_monkey_patches"

module SecurityCenter
  module Export
    class AzureBlobStorageServiceTest < GitHub::TestCase
      fixtures do
        @organization = create(:organization)
      end

      setup do
        @azure_service = mock("Azure::Storage::Blob::BlobService")
        @container_name = "security-center"
        @file_name = "security-center-1.csv"
        @access_key = Base64.strict_encode64("access_key")

        # Stub environment variables
        GitHub.stubs(:security_center_export_azure_blob_container).returns(@container_name)
        GitHub.stubs(:security_center_export_azure_spn_tenant_id).returns("tenant_id")
        GitHub.stubs(:security_center_export_azure_spn_client_id).returns("client_id")
        GitHub.stubs(:security_center_export_azure_spn_client_secret).returns("client_secret")
        GitHub.stubs(:security_center_export_azure_storage_account_name).returns("account")
        GitHub.stubs(:security_center_export_azure_storage_access_key).returns(@access_key)
      end

      class MockedAzureHttpResponse
        attr_reader :status_code, :body, :uri

        def initialize(status_code, body, uri = "")
          @status_code = status_code
          @body = body
          @uri = uri
        end
      end

      context "#create" do
        test "creates an append blob" do
          @azure_service.expects(:create_append_blob).with(@container_name, @file_name, options: { content_type: "text/csv" }).once
          azure_blob_storage_service = AzureBlobStorageService.new
          azure_blob_storage_service.stubs(:client).returns(@azure_service)
          azure_blob_storage_service.create("1")
        end
      end

      context "#store" do
        test "appends to an append blob" do
          @azure_service.expects(:append_blob_block).with(@container_name, @file_name, "abc", options: { content_type: "text/csv" }).once
          azure_blob_storage_service = AzureBlobStorageService.new
          azure_blob_storage_service.stubs(:client).returns(@azure_service)
          azure_blob_storage_service.store("1", "abc", "code_scanning")
        end

        test "raises other errors" do
          @azure_service.expects(:append_blob_block).with(@container_name, @file_name, "abc", options: { content_type: "text/csv" })
            .raises(::Azure::Core::Http::HTTPError.new(MockedAzureHttpResponse.new(500, "error"))).once
          azure_blob_storage_service = AzureBlobStorageService.new
          azure_blob_storage_service.stubs(:client).returns(@azure_service)

          assert_raises ::Azure::Core::Http::HTTPError do
            azure_blob_storage_service.store("1", "abc", "code_scanning")
          end
        end
      end

      context "#retrieve" do
        test "retrieves blob url and size in a BlobServiceResponse" do
          @azure_service.expects(:get_blob_properties).with(@container_name, @file_name).returns(stub(:blob_properties, { properties: { content_length: 123 } })).once
          expected_response = SecurityCenter::Export::BlobStorageService::BlobServiceResponse.new(blob_url: "https://example.com", blob_size: 123)
          azure_blob_storage_service = AzureBlobStorageService.new
          azure_blob_storage_service.stubs(:client).returns(@azure_service)
          azure_blob_storage_service.stubs(:generate_sas_url).returns("https://example.com")

          response = azure_blob_storage_service.retrieve("1", "code_scanning")

          assert response
          assert response&.blob_url, expected_response.blob_url
          assert response&.blob_size, expected_response.blob_size
        end

        test "raises other errors" do
          @azure_service.expects(:get_blob_properties).with(@container_name, @file_name)
            .raises(::Azure::Core::Http::HTTPError.new(MockedAzureHttpResponse.new(500, "error"))).once
          azure_blob_storage_service = AzureBlobStorageService.new
          azure_blob_storage_service.stubs(:client).returns(@azure_service)
          azure_blob_storage_service.stubs(:generate_sas_url).returns("https://example.com")

          assert_raises ::Azure::Core::Http::HTTPError do
            azure_blob_storage_service.retrieve("1", "code_scanning")
          end
        end
      end

      context "#client" do
        test "returns an instance of Azure::Storage::Blob::BlobService signed with an oauth token" do
          azure_blob_storage_service = AzureBlobStorageService.new
          azure_blob_storage_service.stubs(:get_oauth_token).returns(::Azure::Storage::Common::Core::TokenCredential.new("token"))

          client = azure_blob_storage_service.client

          assert_equal client.client.storage_account_name, "account"
          assert client.client.signer.is_a?(::Azure::Storage::Common::Core::Auth::TokenSigner)
          refute client.client.storage_access_key
        end
      end

      context "#get_oauth_token" do
        test "generates a new token credential with expiry when there was no previous one" do
          azure_blob_storage_service = AzureBlobStorageService.new

          refute azure_blob_storage_service.token_credential
          refute azure_blob_storage_service.token_expires

          ::MsRestAzure::ApplicationTokenProvider.any_instance.stubs(:get_authentication_header).returns("header")
          ::MsRestAzure::ApplicationTokenProvider.any_instance.stubs(:token).returns("token")
          ::MsRestAzure::ApplicationTokenProvider.any_instance.stubs(:token_expires_on).returns(Time.now.utc + 1.hour)

          azure_blob_storage_service.get_oauth_token

          assert azure_blob_storage_service.token_credential
          assert azure_blob_storage_service.token_expires
        end


        test "generates a new token credential if the existing one has expired" do
          now = Time.now.utc
          azure_blob_storage_service = AzureBlobStorageService.new
          old_token = ::Azure::Storage::Common::Core::TokenCredential.new("token")
          old_expiry = now + 1.hour

          Timecop.freeze(now) do
            azure_blob_storage_service.instance_variable_set(:@token_credential, old_token)
            azure_blob_storage_service.instance_variable_set(:@token_expires, old_expiry)

            assert azure_blob_storage_service.token_credential
            assert azure_blob_storage_service.token_expires
          end

          Timecop.travel(now + 2.hours) do
            assert azure_blob_storage_service.token_expires

            ::MsRestAzure::ApplicationTokenProvider.any_instance.stubs(:get_authentication_header).returns("header")
            ::MsRestAzure::ApplicationTokenProvider.any_instance.stubs(:token).returns("new_token")
            ::MsRestAzure::ApplicationTokenProvider.any_instance.stubs(:token_expires_on).returns(Time.now.utc + 1.hour)

            azure_blob_storage_service.get_oauth_token

            refute_equal azure_blob_storage_service.token_credential, old_token
            assert_operator azure_blob_storage_service.token_expires, :>, old_expiry
          end
        end

        test "returns the existing token credential if it has not expired" do
          now = Time.now.utc
          azure_blob_storage_service = AzureBlobStorageService.new

          Timecop.freeze(now) do
            azure_blob_storage_service.instance_variable_set(:@token_credential, ::Azure::Storage::Common::Core::TokenCredential.new("token"))
            azure_blob_storage_service.instance_variable_set(:@token_expires, now + 1.hour)

            assert azure_blob_storage_service.token_credential
            assert azure_blob_storage_service.token_expires

            ::MsRestAzure::ApplicationTokenProvider.any_instance.expects(:get_authentication_header).never
            ::MsRestAzure::ApplicationTokenProvider.any_instance.expects(:token).never
            ::MsRestAzure::ApplicationTokenProvider.any_instance.expects(:token_expires_on).never

            existing_token = azure_blob_storage_service.token_credential
            token_credential = azure_blob_storage_service.get_oauth_token

            assert_equal token_credential, existing_token
          end
        end
      end

      context "#generate_sas_url" do
        test "returns a signed url with a user delegation key" do
          mock_key = Azure::Storage::Common::Service::UserDelegationKey.new.tap do |key|
            key.signed_expiry = Time.now.utc + 1.hour
            key.signed_oid = "oid"
            key.signed_service = "service"
            key.signed_start = Time.now.utc
            key.signed_tid = "tid"
            key.signed_version = "1.0"
            key.value = "key"
          end

          mock_sas = Azure::Storage::Common::Core::Auth::SharedAccessSignature.new("account", "", mock_key)
          token_credential = ::Azure::Storage::Common::Core::TokenCredential.new("token")
          mock_client = ::Azure::Storage::Blob::BlobService.create({
            storage_account_name: "account",
            signer: Azure::Storage::Common::Core::Auth::TokenSigner.new(token_credential)
          })

          azure_blob_storage_service = AzureBlobStorageService.new
          azure_blob_storage_service.stubs(:client).returns(mock_client)
          mock_client.stubs(:get_user_delegation_key).returns(mock_key)

          ::Azure::Storage::Common::Core::Auth::SharedAccessSignature.expects(:new).with("account", "", mock_key).returns(mock_sas)
          mock_sas.stubs(:generate_service_sas_token).returns("sas_token")

          azure_blob_storage_service.generate_sas_url("1", "file.csv")
        end
      end
    end
  end
end
