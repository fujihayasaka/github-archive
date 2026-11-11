RSpec.describe Billingd::Client do
  include TwirpTestHelpers

  context "CustomersAPI" do
    describe "#customers" do
      let(:request_params) do
        {
          billable_entities: [
            { billable_entity_type: "Organization", billable_entity_id: 100 },
          ],
        }
      end

      before do
        stub_twirp_rpc("http://localhost:8990/twirp", "billingcore.customers.v1.CustomersAPI", "GetCustomersByBillableEntity")
          .with(twirp_request(
            "billingcore.customers.v1.GetCustomersByBillableEntityRequest",
            **request_params,
          ))
          .to_return twirp_response(
            "billingcore.customers.v1.GetCustomersByBillableEntityResponse",
            customer_accounts: [
              { billable_entity_type: "Organization", billable_entity_id: 100, customer_id: 42 },
            ],
          )
      end

      it "calls CustomersAPI endpoint" do
        response = described_class.new(hmac_key: "billingd").customers.get_customers_by_billable_entity(**request_params)

        expect(response.data.class).to eq BillingCore::Customers::V1::GetCustomersByBillableEntityResponse
        expect(response.data.customer_accounts.first.customer_id).to eq 42
      end
    end
  end
end
