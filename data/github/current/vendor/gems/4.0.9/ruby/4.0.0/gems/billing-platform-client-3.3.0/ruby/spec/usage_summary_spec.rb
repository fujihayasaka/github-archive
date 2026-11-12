RSpec.describe BillingPlatform::Client do
  include TwirpTestHelpers

  context "UsageReportApi" do
    describe "#get_usage_summary" do
      let(:request_params) do
        {
          customerId: "123",
          year: 2023,
          month: 2,
          billingPeriod: :Monthly
        }
      end

      it "calls GetUsageSummary endpoint via UsageReportApi" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.UsageReportApi", "GetUsageSummary")
          .with(twirp_request(
            "billing_platform.api.v1.GetUsageSummaryRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetUsageSummaryResponse"
          )

        response = described_class.new(hmac_key: "billing-platform").get_usage_summary(**request_params)
        expect(response.data.class).to eq BillingPlatform::Api::V1::GetUsageSummaryResponse
      end
    end
  end
end
