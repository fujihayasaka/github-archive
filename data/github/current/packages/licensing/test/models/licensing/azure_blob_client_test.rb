# typed: true
# frozen_string_literal: true

require "test_helper"
require "azure/storage/common"
require "azure/storage/blob"
require "azure/core/http/http_error"
require "azure/core/http/http_response"

class Licensing::AzureBlobClientTest < GitHub::TestCase
  include DogstatsTestHelpers

  setup do
    @azure_service = mock("Azure::Storage::Blob::BlobService")
  end

  class MockedAzureHttpResponse
    attr_reader :status_code, :body, :uri

    def initialize(status_code = 404, body = "Not found", uri = "")
      @status_code = status_code
      @body = body
      @uri = uri
    end
  end

  context "#upload" do
    test "sends the data to the azure blob client" do
      @azure_service.expects(:create_block_blob)
        .with("container", "1", "abc", options: {})
        .returns(Azure::Storage::Blob::Blob.new).once
      azure_blob_client = Licensing::AzureBlobClient.new
      azure_blob_client.stubs(:client).returns(@azure_service)
      azure_blob_client.upload("container", "1", "abc")
    end
  end

  context "#get_blob" do
    test "returns nil if the blob does not exist" do
      @azure_service.expects(:get_blob).with("container", "unknown")
        .raises(::Azure::Core::Http::HTTPError.new(MockedAzureHttpResponse.new)).once
      azure_blob_client = Licensing::AzureBlobClient.new
      azure_blob_client.stubs(:client).returns(@azure_service)
      (blob, data) = azure_blob_client.get_blob("container", "unknown")

      assert_nil blob
      assert_nil data
    end

    test "raises other errors" do
      @azure_service.expects(:get_blob).with("container", "1")
        .raises(::Azure::Core::Http::HTTPError.new(MockedAzureHttpResponse.new(500, "error"))).once
      azure_blob_client = Licensing::AzureBlobClient.new
      azure_blob_client.stubs(:client).returns(@azure_service)

      assert_raises ::Licensing::AzureBlobClient::GetBlobError do
        azure_blob_client.get_blob("container", "1")
      end
    end

    test "returns the data if it exists" do
      expected_blob = Azure::Storage::Blob::Blob.new
      expected_data = "abc"
      @azure_service.expects(:get_blob).with("container", "1")
        .returns([expected_blob, expected_data]).once
      azure_blob_client = Licensing::AzureBlobClient.new
      azure_blob_client.stubs(:client).returns(@azure_service)
      (actual_blob, actual_data) = azure_blob_client.get_blob("container", "1")

      assert_equal actual_blob, expected_blob
      assert_equal actual_data, expected_data
    end
  end
end
