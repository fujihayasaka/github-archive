# typed: true
# frozen_string_literal: true

require "test_helper"
require "azure/storage/common"
require "azure/storage/blob"
require "azure/core/http/http_error"
require "azure/core/http/http_response"

class Licensing::GhesKeypairTest < GitHub::TestCase
  setup do
    @azure_client = mock("Azure::Storage::Blob::BlobService")
    Licensing::GhesKeypair.stubs(:azure_blob_client).returns(@azure_client)
  end

  context "#save!" do
    test "sends the data to the azure blob client" do
      params = {
        business_id: "1",
        secret_key_data: "secret_key_data",
        public_key_data: "public_key_data",
        support_secret_key: "support_secret_key",
        support_public_key: "support_public_key"
      }
      ghes_keypair = Licensing::GhesKeypair.new(**params)
      @azure_client.expects(:upload).with(Licensing::GhesKeypair::GHES_KEYPAIRS_CONTAINER, "business:1", params.to_json).once
      ghes_keypair.save!
    end
  end

  context "#find_by_business_id" do
    test "returns nil if the blob does not exist" do
      @azure_client.expects(:get_blob).with(Licensing::GhesKeypair::GHES_KEYPAIRS_CONTAINER, "business:unknown")
        .returns(nil, nil).once
      assert_nil Licensing::GhesKeypair.get_by_business_id("unknown")
    end

    test "returns the data if it exists" do
      data = {
        business_id: "1",
        secret_key_data: "secret_key_data",
        public_key_data: "public_key_data",
        support_secret_key: "support_secret_key",
        support_public_key: "support_public_key"
      }
      @azure_client.expects(:get_blob).with(Licensing::GhesKeypair::GHES_KEYPAIRS_CONTAINER, "business:1")
        .returns([Azure::Storage::Blob::Blob.new, data.to_json]).once
      ghes_keypair = Licensing::GhesKeypair.get_by_business_id("1")

      assert_equal data[:business_id], T.must(ghes_keypair).business_id
      assert_equal data[:secret_key_data], T.must(ghes_keypair).secret_key_data
      assert_equal data[:public_key_data], T.must(ghes_keypair).public_key_data
      assert_equal data[:support_secret_key], T.must(ghes_keypair).support_secret_key
      assert_equal data[:support_public_key], T.must(ghes_keypair).support_public_key
    end
  end
end
