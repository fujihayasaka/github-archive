RSpec.describe Billingd::Client do
  include TwirpTestHelpers

  context "SubscriptionAPI" do
    describe "#subscriptions" do
      let(:request_params) do
        {
          entity_id: 123,
          entity_type: "organization",
          product_keys: ["copilot_for_business"],
        }
      end

      before do
        stub_twirp_rpc("http://localhost:8990/twirp", "billingcore.subscription.v1.SubscriptionAPI", "GetProductSubscriptionStatus")
          .with(twirp_request(
            "billingcore.subscription.v1.GetProductSubscriptionStatusRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billingcore.subscription.v1.GetProductSubscriptionStatusResponse",
            status: :PRODUCT_SUBSCRIPTION_STATUS_ACTIVE,
          )
      end

      it "calls SubscriptionAPI endpoint" do
        response = described_class.new(hmac_key: "billingd").subscriptions.get_product_subscription_status(**request_params)

        expect(response.data.class).to eq BillingCore::Subscription::V1::GetProductSubscriptionStatusResponse
        expect(response.data.status).to eq :PRODUCT_SUBSCRIPTION_STATUS_ACTIVE
      end
    end
  end
end
