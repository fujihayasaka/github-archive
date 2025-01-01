RSpec.describe BillingPlatform::Client do
  include TwirpTestHelpers

  context "CopilotUsageApi" do
    describe "#get_copilot_usage_table" do
      let(:request_params) do
        {
          customerId: "123",
          year: 2023,
          month: 2,
          billingPeriod: :Monthly
        }
      end

      it "calls GetCopilotUsageTable endpoint" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.CopilotUsageApi", "GetCopilotUsageTable")
          .with(twirp_request(
            "billing_platform.api.v1.GetCopilotUsageTableRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetCopilotUsageTableResponse"
          )

        response = described_class.new(hmac_key: "billing-platform").get_copilot_usage_table(**request_params)
        expect(response.data.class).to eq BillingPlatform::Api::V1::GetCopilotUsageTableResponse
      end
    end

    describe "#get_copilot_usage_chart_data" do
      let(:request_params) do
        {
          customerId: "123",
          year: 2023,
          month: 2,
          billingPeriod: :Monthly
        }
      end

      it "calls GetCopilotUsageChartData endpoint" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.CopilotUsageApi", "GetCopilotUsageChartData")
          .with(twirp_request(
            "billing_platform.api.v1.GetCopilotUsageChartDataRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetUsageChartDataResponse"
          )

        response = described_class.new(hmac_key: "billing-platform").get_copilot_usage_chart_data(**request_params)
        expect(response.data.class).to eq BillingPlatform::Api::V1::GetUsageChartDataResponse
      end
    end

    describe "#get_copilot_usage_card_data" do
      let(:request_params) do
        {
          customerId: "123",
          year: 2023,
          month: 2,
          billingPeriod: :Monthly
        }
      end

      it "calls GetCopilotUsageCardData endpoint" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.CopilotUsageApi", "GetCopilotUsageCardData")
          .with(twirp_request(
            "billing_platform.api.v1.GetCopilotUsageCardDataRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetUsageCardDataResponse"
          )

        response = described_class.new(hmac_key: "billing-platform").get_copilot_usage_card_data(**request_params)
        expect(response.data.class).to eq BillingPlatform::Api::V1::GetUsageCardDataResponse
      end
    end

    describe "#get_copilot_model" do
      let(:request_params) do
        {}
      end

      it "calls GetCopilotModels endpoint" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.CopilotUsageApi", "GetCopilotModels")
          .with(twirp_request(
            "billing_platform.api.v1.GetCopilotModelsRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetCopilotModelsResponse"
          )

        response = described_class.new(hmac_key: "billing-platform").get_copilot_models
        expect(response.data.class).to eq BillingPlatform::Api::V1::GetCopilotModelsResponse
      end
    end

    describe "#get_copilot_usage_report" do
      let(:request_params) do
        {
          customerId: "123",
          year: 2023,
          month: 2,
          day: 15,
          billingPeriod: :Monthly,
          orgId: 456,
          userId: 789,
          model: "gpt-4",
          product: "copilot",
          costCenterId: "cost-center-123"
        }
      end

      it "calls GetCopilotUsageReport endpoint" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.CopilotUsageApi", "GetCopilotUsageReport")
          .with(twirp_request(
            "billing_platform.api.v1.GetCopilotUsageReportRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetCopilotUsageReportResponse"
          )

        response = described_class.new(hmac_key: "billing-platform").get_copilot_usage_report(**request_params)
        expect(response.data.class).to eq BillingPlatform::Api::V1::GetCopilotUsageReportResponse
      end
    end
  end
end
