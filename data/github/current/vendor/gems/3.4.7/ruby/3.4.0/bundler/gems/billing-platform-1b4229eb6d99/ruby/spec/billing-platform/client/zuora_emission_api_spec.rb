RSpec.describe BillingPlatform::Client do
  include TwirpTestHelpers

  context "ZouraEmissionApi" do
    describe "#get_zuora_emissions" do
      let(:request_params) do
        {
          customerId: "123",
          year: 2021,
          month: 1,
          day: 1,
        }
      end

      before do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.ZuoraEmissionAPI", "GetZuoraEmissions")
          .with(twirp_request(
            "billing_platform.api.v1.GetZuoraEmissionsRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetZuoraEmissionsResponse"
          )
      end

      it "calls ZuoraEmissionAPI endpoint" do
        response = described_class.new(hmac_key: "billing-platform").get_zuora_emissions(**request_params)

        expect(response.data.emissions).to be_empty
      end
    end
  end
end
