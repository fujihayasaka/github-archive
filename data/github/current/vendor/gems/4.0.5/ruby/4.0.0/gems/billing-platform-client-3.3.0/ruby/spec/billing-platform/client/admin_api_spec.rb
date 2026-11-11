RSpec.describe BillingPlatform::Client do
  include TwirpTestHelpers

  context "AdminApi" do
    describe "#admin_trigger_invoice_generation" do
      let(:request_params) do
        {
          customerId: "123",
          year: 2023,
          month: 6,
        }
      end

      it "calls the AdminApi service with the trigger invoice generation method" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.AdminApi",
          "TriggerInvoiceGeneration"
        ).with(twirp_request(
          "billing_platform.api.v1.TriggerInvoiceGenerationRequest",
          **request_params,
        )).to_return(twirp_response("billing_platform.api.v1.TriggerInvoiceGenerationResponse"))

        response = described_class.new(hmac_key: "billing-platform")
          .admin_trigger_invoice_generation(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::TriggerInvoiceGenerationResponse
      end
    end

    describe "#admin_process_dead_letter_queue" do
      let(:request_params) do
        {
          num: 1
        }
      end

      before do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.AdminApi", "ProcessDeadLetterQueue")
          .with(twirp_request(
            "billing_platform.api.v1.ProcessDeadLetterQueueRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.ProcessDeadLetterQueueResponse",
          )
      end

      it "calls AdminApi endpoint" do
        response = described_class.new(hmac_key: "billing-platform").admin_process_dead_letter_queue(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::ProcessDeadLetterQueueResponse
      end
    end

    describe "#admin_trigger_azure_emission no customer ID" do
      let(:request_params) do
        {
          year: 2023,
          month: 6,
          day: 1
        }
      end

      before do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.AdminApi", "TriggerAzureEmission")
          .with(twirp_request(
            "billing_platform.api.v1.TriggerAzureEmissionRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.TriggerAzureEmissionResponse",
          )
      end

      it "calls AdminApi endpoint" do
        response = described_class.new(hmac_key: "billing-platform").admin_trigger_azure_emission(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::TriggerAzureEmissionResponse
      end
    end

    describe "#admin_trigger_azure_emission with customer ID" do
      let(:request_params) do
        {
          customerId: "123",
          year: 2023,
          month: 6,
          day: 1
        }
      end

      before do
        stub_twirp_rpc("http://localhost:8989/twirp", "billing_platform.api.v1.AdminApi", "TriggerAzureEmission")
          .with(twirp_request(
            "billing_platform.api.v1.TriggerAzureEmissionRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billing_platform.api.v1.TriggerAzureEmissionResponse",
          )
      end

      it "calls AdminApi endpoint" do
        response = described_class.new(hmac_key: "billing-platform").admin_trigger_azure_emission(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::TriggerAzureEmissionResponse
      end
    end

    describe "#admin_get_azure_emissions" do
      let(:request_params) do
        {
          customerId: "123",
          product: "actions",
          year: 2023,
          month: 6,
          day: 20
        }
      end

      it "calls the AdminApi service with get azure emissions method" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.AdminApi",
          "GetAzureEmissions"
        ).with(twirp_request(
          "billing_platform.api.v1.GetAzureEmissionsRequest",
          **request_params,
        )).to_return(twirp_response("billing_platform.api.v1.GetAzureEmissionsResponse"))

        response = described_class.new(hmac_key: "billing-platform")
          .admin_get_azure_emissions(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::GetAzureEmissionsResponse
      end
    end

    describe "#admin_get_pooled_entitlement" do
      let(:request_params) do
        {
          customerID: 123,
        }
      end

      it "calls the AdminApi service with the get pooled entitlement method" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.AdminApi",
          "GetPooledEntitlement"
        ).with(twirp_request(
          "billing_platform.api.v1.GetPooledEntitlementRequest",
          **request_params,
        )).to_return(twirp_response("billing_platform.api.v1.GetPooledEntitlementResponse"))

        response = described_class.new(hmac_key: "billing-platform")
          .admin_get_pooled_entitlement(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::GetPooledEntitlementResponse
      end
    end

    describe "#admin_refresh_pooled_entitlement" do
      let(:request_params) do
        {
          customerID: 123,
          copilotForBusinessCount: 10,
          copilotEnterpriseCount: 5,
        }
      end

      it "calls the AdminApi service with the refresh pooled entitlement method" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.AdminApi",
          "RefreshPooledEntitlement"
        ).with(twirp_request(
          "billing_platform.api.v1.RefreshPooledEntitlementRequest",
          **request_params,
        )).to_return(twirp_response("billing_platform.api.v1.RefreshPooledEntitlementResponse"))

        response = described_class.new(hmac_key: "billing-platform")
          .admin_refresh_pooled_entitlement(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::RefreshPooledEntitlementResponse
      end
    end

    describe "#admin_reset_pooled_entitlement_current_amount" do
      let(:request_params) do
        {
          customerID: 123,
          currentAmount: 25.5,
        }
      end

      it "calls the AdminApi service with the reset pooled entitlement current amount method" do
        stub_twirp_rpc(
          "http://localhost:8989/twirp",
          "billing_platform.api.v1.AdminApi",
          "ResetPooledEntitlementCurrentAmount"
        ).with(twirp_request(
          "billing_platform.api.v1.ResetPooledEntitlementCurrentAmountRequest",
          **request_params,
        )).to_return(twirp_response("billing_platform.api.v1.ResetPooledEntitlementCurrentAmountResponse"))

        response = described_class.new(hmac_key: "billing-platform")
          .admin_reset_pooled_entitlement_current_amount(**request_params)

        expect(response.data.class).to eq BillingPlatform::Api::V1::ResetPooledEntitlementCurrentAmountResponse
      end
    end
  end
end
