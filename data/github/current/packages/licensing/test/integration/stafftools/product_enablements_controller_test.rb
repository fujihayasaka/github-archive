# typed: strict
# frozen_string_literal: true

require "test_helper"

class StafftoolsProductEnablementsControllerHttpTest < GitHub::IntegrationTestCase
  include Licensing::Licensify

  fixtures do
    @customer_id = T.let(create(:customer).id, T.nilable(Integer))
    @staff = T.let(create(:staff_admin_user), T.nilable(User))
  end

  context "#index" do
    test "returns product enablements" do
      ::Licensify::Client.any_instance.expects(:get_product_enablements)
        .with(Licensify::Services::V1::GetProductEnablementsRequest.new(customerId: T.must(@customer_id)))
        .returns(Twirp::ClientResp.new(
          data: ::Licensify::Services::V1::GetProductEnablementsResponse.new,
          error: nil,
        )).once

      as @staff
      get "/stafftools/product_enablements?customer_id=#{T.must(@customer_id)}", as: :json

      assert_response :ok
    end
  end

  context "#create" do
    test "calls the Licensify service to upsert a product enablement" do
      product_enablement = Licensify::Services::V1::ProductEnablement.new(
        customerId: @customer_id,
        product: Licensify::Services::V1::Product::PRODUCT_GHAS,
        enablementType: Licensify::Services::V1::ProductEnablementType::PRODUCT_ENABLEMENT_TYPE_REPO,
        enablementId: 100,
        globalId: "global-id-100",
        enabledAt: Google::Protobuf::Timestamp.new(seconds: 1234567890),
      )
      req = Licensify::Services::V1::UpsertProductEnablementRequest.new(productEnablement: product_enablement)
      ::Licensify::Client.any_instance.expects(:upsert_product_enablement)
        .with(req)
        .returns(Twirp::ClientResp.new(
          data: ::Licensify::Services::V1::UpsertProductEnablementResponse.new,
          error: nil,
        )).once

      as @staff
      post "/stafftools/product_enablements", params: req, as: :json

      assert_response :ok
    end

    test "returns the twirp error when the twirp request errors" do
      ::Licensify::Client.any_instance.expects(:upsert_product_enablement)
        .returns(Twirp::ClientResp.new(
          data: nil,
          error: Twirp::Error.invalid_argument("missing product", argument: "request.productEnablement.product")
        )).once

      as @staff
      post "/stafftools/product_enablements", params: {
        productEnablement: {
          customerId: @customer_id,
        }
      }, as: :json

      assert_response :bad_request
      assert_match "missing product", response.body
    end

    test "returns bad request when the request cannot be parsed" do
      ::Licensify::Client.any_instance.expects(:upsert_product_enablement).never

      as @staff
      post "/stafftools/product_enablements", params: {
        productEnablement: {
          customerId: @customer_id,
          product: "invalid"
        }
      }, as: :json

      assert_response :bad_request
      assert_match "Invalid request body: Error occurred during parsing: Enum value unknown: 'invalid'", response.body
    end
  end
end
