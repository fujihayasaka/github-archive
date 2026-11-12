RSpec.describe BillingPlatform::Client do
  include TwirpTestHelpers

  context "ProductApi" do
    describe "#get_all_products" do
      it "calls ProductAPI endpoint" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.ProductApi", "GetAllProducts")
          .with(twirp_request(
            "billing_platform.api.v1.GetAllProductsRequest",
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetAllProductsResponse",
            products: [
              BillingPlatform::Api::V1::Product.new(
                name: "codespaces",
                friendlyProductName: "Codespaces",
              ),
              BillingPlatform::Api::V1::Product.new(
                name: "actions",
                friendlyProductName: "Actions",
              ),
            ]
          )
        response = described_class.new(hmac_key: "billing-platform").get_all_products()

        expect(response.data.products.count).to eq 2
        expect(response.data.products.collect(&:name)).to contain_exactly("codespaces", "actions")
      end
    end

    describe "#get_product" do
      it "calls ProductAPI endpoint" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.ProductApi", "GetProduct") .with(twirp_request(
          "billing_platform.api.v1.GetProductRequest",
          product: "codespaces",
        ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetProductResponse",
            product: BillingPlatform::Api::V1::Product.new(name: "codespaces", friendlyProductName: "Codespaces"),
          )

        response = described_class.new(hmac_key: "billing-platform").get_product("codespaces")
        expect(response.data.product.name).to eq("codespaces")
      end
    end

    describe "#create_or_update_product" do
      it "raises a deprecation error" do
        request_params = {
          name: "codespaces",
          friendlyProductName: "Codespaces",
        }

        api_client = described_class.new(hmac_key: "billing-platform")
        expect { api_client.create_or_update_product(**request_params) }.to raise_error(
          "create_or_update_product is deprecated"
        )
      end
    end
  end
end
