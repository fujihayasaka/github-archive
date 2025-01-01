# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::LicensifyTest < GitHub::TestCase
  setup do
    @subject = Class.new { include Licensing::Licensify }.new
  end

  context "#initialize" do
    test "initialize a client" do
      assert_instance_of ::Licensify::Client, @subject.licensify_client
    end
  end

  context "#get_product_enablements" do
    test "delegates to the licensify_client" do
      request = Licensify::Services::V1::GetProductEnablementsRequest.new(customerId: 3)
      response = Licensify::Services::V1::GetProductEnablementsResponse.new(
        productEnablements: []
      )
      @subject.licensify_client.expects(:get_product_enablements)
        .with(request).returns(response).once

      assert_equal response, @subject.licensify_client.get_product_enablements(request)
    end
  end

  context "#upsert_product_enablement" do
    test "delegates to the licensify_client" do
      request = Licensify::Services::V1::UpsertProductEnablementRequest.new(
        productEnablement: {
          customerId: 1,
          product: Licensify::Services::V1::Product::PRODUCT_GHAS,
          enablementId: 60,
          globalId: "id-1",
          enablementType: Licensify::Services::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO,
          enabledAt: Google::Protobuf::Timestamp.new(seconds: Time.now.to_i)
        }
      )
      response = Licensify::Services::V1::UpsertProductEnablementResponse.new
      @subject.licensify_client.expects(:upsert_product_enablement)
        .with(request).returns(response).once

      assert_equal response, @subject.licensify_client.upsert_product_enablement(request)
    end
  end
end
