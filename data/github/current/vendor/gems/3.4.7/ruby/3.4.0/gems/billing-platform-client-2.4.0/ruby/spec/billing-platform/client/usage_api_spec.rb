RSpec.describe BillingPlatform::Client do
  include TwirpTestHelpers

  context "UsageApi" do
    describe "#get_top_org_repo_usage_line_items" do
      let(:request_params) do
        {
          customerId: 123,
          limit: 5,
          year: 2023,
          month: 2,
          day: 7,
          hour: 14,
          billingPeriod: :Hourly,
          groupBy: :NoGroupBy,
        }
      end

      before do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.UsageApi", "GetTopOrgRepoUsageLineItems")
          .with(twirp_request(
            "billing_platform.api.v1.TopOrgRepoUsageRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.TopOrgRepoUsageResponse",
          )
      end

      it "calls TopUsageLineItems endpoint" do
        response = described_class.new(hmac_key: "billing-platform").get_top_org_repo_usage_line_items(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::TopOrgRepoUsageResponse
      end
    end

    describe "#get_usage_total" do
      param_test_cases = [
        [
          "all params",
          {
            usageEntityId: "123",
            sku: "actions_linux_64_core",
            year: 2023,
            month: 2,
            day: 7,
            hour: 14,
            billingPeriod: :Hourly
          }
        ],
        [
          "missing sku",
          {
            usageEntityId: "123",
            year: 2023,
            month: 2,
            day: 7,
            hour: 14,
            billingPeriod: :Hourly
          }
        ],
        [
          "missing hour",
          {
            usageEntityId: "123",
            sku: "actions_linux_64_core",
            year: 2023,
            month: 2,
            day: 7,
            billingPeriod: :Hourly
          }
        ],
        [
          "missing billingPeriod",
          {
            usageEntityId: "123",
            sku: "actions_linux_64_core",
            year: 2023,
            month: 2,
            day: 7,
            hour: 14,
          }
        ]
      ]

      param_test_cases.each do |test_case, params|
        it "calls UsageAPI endpoint - #{test_case}" do
          params_with_customer_id = params.clone
          params_with_customer_id[:customerId] = params_with_customer_id.delete(:usageEntityId)
          stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.UsageApi", "GetUsageTotal")
          .with(twirp_request(
            "billing_platform.api.v1.GetUsageRequest",
            **params_with_customer_id,
            # The client is going to pass an extra usageEntityId field for now, so our intercepter needs to expect it
            usageEntityId: params_with_customer_id[:customerId],
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetUsageResponse",
            sku: "actions_linux_64_core",
            quantity: 123,
            billableAmount: 5.99
          )
          response = described_class.new(hmac_key: "billing-platform").get_usage_total(**params_with_customer_id)

          expect(response.data.sku).to eq "actions_linux_64_core"
          expect(response.data.quantity).to eq 123
          expect(response.data.billableAmount).to eq 5.99
        end
      end

      param_test_cases.each do |test_case, params|
        it "calls UsageAPI endpoint without customerId - #{test_case}" do
          stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.UsageApi", "GetUsageTotal")
          .with(twirp_request(
            "billing_platform.api.v1.GetUsageRequest",
            **params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetUsageResponse",
            sku: "actions_linux_64_core",
            quantity: 123,
            billableAmount: 5.99
          )
          response = described_class.new(hmac_key: "billing-platform").get_usage_total(**params)

          expect(response.data.sku).to eq "actions_linux_64_core"
          expect(response.data.quantity).to eq 123
          expect(response.data.billableAmount).to eq 5.99
        end
      end
    end

    describe "#get_enterprise_usage_totals" do
      param_test_cases = [
        [
          "all params",
          {
            customerId: "123",
            year: 2023,
            month: 2,
            organizationAdminIds: [1, 2, 3],
          }
        ],
        [
          "missing organizationAdminIds",
          {
            customerId: "123",
            year: 2023,
            month: 2,
          }
        ],
      ]

      param_test_cases.each do |test_case, params|
        it "calls UsageAPI endpoint - #{test_case}" do
          stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.UsageApi", "GetEnterpriseUsageTotals")
          .with(twirp_request(
            "billing_platform.api.v1.GetEnterpriseUsageTotalsRequest",
            **params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetEnterpriseUsageTotalsResponse",
          )

          response = described_class.new(hmac_key: "billing-platform").get_enterprise_usage_totals(**params)
          expect(response.data.class).to eq BillingPlatform::Api::V1::GetEnterpriseUsageTotalsResponse
        end
      end
    end

    describe "#get_usage_line_items" do
      let(:request_params) do
        {
          usageEntityId: "123",
          sku: "actions_linux_64_core",
          orgId: 100,
          repoId: 123,
          year: 2023,
          month: 2,
          day: 7,
          hour: 14,
          billingPeriod: :Hourly,
          groupBy: :NoGroupBy
        }
      end

      it "raises a deprecation error" do
        api_client = described_class.new(hmac_key: "billing-platform")

        expect { api_client.get_usage_line_items(**request_params) }.to raise_error(
          "get_usage_line_items is deprecated. Use get_top_org_repo_usage_line_items instead."
        )
      end
    end

    describe "#get_discount_line_items" do
      let(:request_params) do
        {
          usageEntityId: "123",
          sku: "actions_linux_64_core",
          orgId: 100,
          repoId: 123,
          year: 2023,
          month: 2,
          day: 7,
          hour: 14,
          billingPeriod: :Hourly,
          groupBy: :NoGroupBy
        }
      end

      it "raises a deprecation error" do
        api_client = described_class.new(hmac_key: "billing-platform")

        expect { api_client.get_discount_line_items(**request_params) }.to raise_error(
          "get_discount_line_items is deprecated. Use get_net_usage_line_items instead."
        )
      end
    end

    describe "#get_net_usage_line_items" do
      let(:request_params_with_customer_id) do
        {
          customerId: "123",
          year: 2023,
          month: 2
        }
      end
      let(:request_params) do
        {
          usageEntityId: "123",
          year: 2023,
          month: 2
        }
      end

      it "calls UsageAPI endpoint" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.UsageApi", "GetNetUsageLineItems")
          .with(twirp_request(
            "billing_platform.api.v1.GetUsageRequest",
            **request_params_with_customer_id,
            # The client is going to pass an extra usageEntityId field for now, so our intercepter needs to expect it
            usageEntityId: "123",
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetNetUsageLineItemsResponse"
          )

        response = described_class.new(hmac_key: "billing-platform").get_net_usage_line_items(**request_params_with_customer_id)
        expect(response.data.class).to eq BillingPlatform::Api::V1::GetNetUsageLineItemsResponse
      end

      it "calls UsageAPI endpoint without customerId" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.UsageApi", "GetNetUsageLineItems")
          .with(twirp_request(
            "billing_platform.api.v1.GetUsageRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.GetNetUsageLineItemsResponse"
          )

        response = described_class.new(hmac_key: "billing-platform").get_net_usage_line_items(**request_params)
        expect(response.data.class).to eq BillingPlatform::Api::V1::GetNetUsageLineItemsResponse
      end
    end

    describe "#get_watermark_level" do
      let(:request_params_with_customer_id) do
        {
          customerId: "123",
          sku: "actions_storage",
          orgId: 15,
          repoId: 456
        }
      end

      let(:request_params) do
        {
          usageEntityId: "123",
          sku: "actions_storage",
          orgId: 15,
          repoId: 456
        }
      end

      it "calls UsageAPI endpoint" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.UsageApi", "GetWatermarkLevel")
        .with(twirp_request(
          "billing_platform.api.v1.GetWatermarkLevelRequest",
          **request_params_with_customer_id,
          # The client is going to pass an extra usageEntityId field for now, so our intercepter needs to expect it
          usageEntityId: "123",
        ))
        .to_return twirp_response(
          "billing_platform.api.v1.GetWatermarkLevelResponse",
          sku: "actions_storage",
          quantity: 123,
        )
        response = described_class.new(hmac_key: "billing-platform").get_watermark_level(**request_params_with_customer_id)

        expect(response.data.sku).to eq "actions_storage"
        expect(response.data.quantity).to eq 123
      end

      it "calls UsageAPI endpoint without customerId" do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.UsageApi", "GetWatermarkLevel")
        .with(twirp_request(
          "billing_platform.api.v1.GetWatermarkLevelRequest",
          **request_params,
        ))
        .to_return twirp_response(
          "billing_platform.api.v1.GetWatermarkLevelResponse",
          sku: "actions_storage",
          quantity: 123,
        )
        response = described_class.new(hmac_key: "billing-platform").get_watermark_level(**request_params)

        expect(response.data.sku).to eq "actions_storage"
        expect(response.data.quantity).to eq 123
      end
    end
  end
end
