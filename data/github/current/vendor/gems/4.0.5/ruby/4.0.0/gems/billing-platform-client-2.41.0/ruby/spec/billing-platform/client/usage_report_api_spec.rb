RSpec.describe BillingPlatform::Client do
  include TwirpTestHelpers

  context "UsageReportApi" do
    describe "#get_usage_report" do
      let(:request_params) do
       {
          usageEntityId: "123",
          year: 2023,
          month: 2,
          day: 7,
          billingPeriod: :Hourly,
          orgId: 789,
        }
      end

      it "calls UsageReportAPI endpoint" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.UsageReportApi",
           "GetUsageReport"
        ).with(twirp_request(
          "billing_platform.api.v1.GetUsageReportRequest",
          **request_params,
        )) .to_return twirp_response("billing_platform.api.v1.GetUsageReportResponse",)

        response = described_class.new(hmac_key: "billing-platform").get_usage_report(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::GetUsageReportResponse
      end
    end

    describe "#queue_usage_report_export" do
      let(:request_params) do
       {
          customerId: "123",
          actorId: 456,
          organizationIds: [789],
          startDate: 1714058444,
          endDate: 1714058444,
          billableOwnerId: 10,
          billableOwnerType: 1,
          reportType: :Legacy,
        }
      end

      it "calls QueueUsageReportExport endpoint" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.UsageReportApi",
           "QueueUsageReportExport"
        ).with(twirp_request(
          "billing_platform.api.v1.QueueUsageReportExportRequest",
          **request_params,
        )) .to_return twirp_response("billing_platform.api.v1.QueueUsageReportExportResponse",)

        response = described_class.new(hmac_key: "billing-platform").queue_usage_report_export(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::QueueUsageReportExportResponse
      end
    end

    describe "#request_usage_report_export" do
      let(:request_params) do
        {
          customerId: "123",
          startDate: 1696118400,
          endDate: 1698796800,
          actorId: 12345,
          organizationIds: [1, 2],
          reportType: :Summarized,
          sendEmail: true,
        }
      end

      it "calls RequestUsageReportExport endpoint" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.UsageReportApi",
          "RequestUsageReportExport"
        ).with(twirp_request(
          "billing_platform.api.v1.RequestUsageReportExportRequest",
          **request_params,
        )).to_return twirp_response("billing_platform.api.v1.RequestUsageReportExportResponse",)

        response = described_class.new(hmac_key: "billing-platform").request_usage_report_export(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::RequestUsageReportExportResponse
      end
    end

    describe "#get_usage_report_export" do
      let(:request_params) do
        {
          customerId: "123",
          exportOperationUuid: "550e8400-e29b-41d4-a716-446655440000",
        }
      end

      it "calls GetUsageReportExport endpoint" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.UsageReportApi",
          "GetUsageReportExport"
        ).with(twirp_request(
          "billing_platform.api.v1.GetUsageReportExportRequest",
          **request_params,
        )).to_return twirp_response("billing_platform.api.v1.GetUsageReportExportResponse",)

        response = described_class.new(hmac_key: "billing-platform").get_usage_report_export(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::GetUsageReportExportResponse
      end
    end

    describe "#get_usage_report_exports" do
      let(:request_params) do
        {
          customerId: "123",
        }
      end

      it "calls GetUsageReportExports endpoint" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.UsageReportApi",
          "GetUsageReportExports"
        ).with(twirp_request(
          "billing_platform.api.v1.GetUsageReportExportsRequest",
          **request_params,
        )).to_return twirp_response("billing_platform.api.v1.GetUsageReportExportsResponse",)

        response = described_class.new(hmac_key: "billing-platform").get_usage_report_exports(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::GetUsageReportExportsResponse
      end
    end
  end
end
