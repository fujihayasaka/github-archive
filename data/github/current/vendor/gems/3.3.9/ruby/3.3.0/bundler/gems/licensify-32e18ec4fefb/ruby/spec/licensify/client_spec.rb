# frozen_string_literal: true

RSpec.describe Licensify::Client do
  include TwirpTestHelpers

  subject(:client) { described_class.new(hmac_key: "licensify") }

  context "when calling ProductEnablementService" do
    describe "#get_product_enablements" do
      it "creates request and parses the response" do
        request_params = { customerId: 10 }
        stubbed_request = stub_twirp_rpc("licensify.services.v1.ProductEnablementService", "GetProductEnablements")
                          .with(twirp_request(
                                  "licensify.services.v1.GetProductEnablementsRequest",
                                  **request_params
                                ))
                          .to_return twirp_response(
                            "licensify.services.v1.GetProductEnablementsResponse",
                            productEnablements: []
                          )

        response = client.get_product_enablements(**request_params)

        expect(stubbed_request).to have_been_requested.once
        expect(response.error).to be_nil
        expect(response.data.class).to eq(Licensify::Services::V1::GetProductEnablementsResponse)
        expect(response.data.productEnablements).to eq([])
      end
    end

    describe "#upsert_product_enablement" do
      it "creates request and parses the response" do
        enabled_at = Time.now
        request_params = {
          productEnablement: {
            customerId: 10,
            product: "PRODUCT_GHAS",
            globalId: "gid://git-hub/User/1",
            enablementType: "PRODUCT_ENABLEMENT_TYPE_ORG",
            enabledAt: Google::Protobuf::Timestamp.new(seconds: enabled_at.to_i, nanos: enabled_at.nsec)
          }
        }

        stubbed_request = stub_twirp_rpc("licensify.services.v1.ProductEnablementService", "UpsertProductEnablement")
                          .with(twirp_request(
                                  "licensify.services.v1.UpsertProductEnablementRequest",
                                  **request_params
                                ))
                          .to_return twirp_response(
                            "licensify.services.v1.UpsertProductEnablementResponse"
                          )

        response = client.upsert_product_enablement(**request_params)

        expect(stubbed_request).to have_been_requested.once
        expect(response.error).to be_nil
        expect(response.data.class).to eq(Licensify::Services::V1::UpsertProductEnablementResponse)
        expect(response.body).to be_empty
      end
    end
  end

  context "when calling CustomerService" do
    describe "#upsert_customer" do
      it "creates request and parses the response" do
        request_params = {
          customer: {
            id: 10,
            sdlcLicensingModel: 2,
            sdlcTrial: false,
          }
        }
        stubbed_request = stub_twirp_rpc("licensify.services.v1.CustomerService", "UpsertCustomer")
                          .with(twirp_request(
                                  "licensify.services.v1.UpsertCustomerRequest",
                                  **request_params
                                ))
                          .to_return twirp_response(
                            "licensify.services.v1.UpsertCustomerResponse"
                          )

        response = client.upsert_customer(**request_params)

        expect(stubbed_request).to have_been_requested.once
        expect(response.error).to be_nil
        expect(response.data.class).to eq(Licensify::Services::V1::UpsertCustomerResponse)
        expect(response.body).to be_empty
      end
    end
  end

  context "when calling CustomerLicenseService" do
    describe "#get_licensee_global_ids" do
      it "creates request and parses the response" do
        request_params = {
          customerId: 10,
          product: "PRODUCT_SDLC"
        }
        stubbed_request = stub_twirp_rpc("licensify.services.v1.CustomerLicenseService", "GetLicenseeGlobalIds")
                          .with(twirp_request(
                                  "licensify.services.v1.GetLicenseeGlobalIdsRequest",
                                  **request_params
                                ))
                          .to_return twirp_response(
                            "licensify.services.v1.GetLicenseeGlobalIdsResponse",
                            globalIds: ["gid://git-hub/User/1"]
                          )

        response = client.get_licensee_global_ids(**request_params)

        expect(stubbed_request).to have_been_requested.once
        expect(response.error).to be_nil
        expect(response.data.class).to eq(Licensify::Services::V1::GetLicenseeGlobalIdsResponse)
        expect(response.data.globalIds).to eq(["gid://git-hub/User/1"])
      end
    end

    describe "#get_customer_licenses" do
      it "creates request and parses the response" do
        request_params = {
          customerId: 10,
          product: "PRODUCT_SDLC"
        }
        stubbed_request = stub_twirp_rpc("licensify.services.v1.CustomerLicenseService", "GetCustomerLicenses")
                          .with(twirp_request(
                                  "licensify.services.v1.GetCustomerLicensesRequest",
                                  **request_params
                                ))
                          .to_return twirp_response(
                            "licensify.services.v1.GetCustomerLicensesResponse",
                            customerLicenses: []
                          )

        response = client.get_customer_licenses(**request_params)

        expect(stubbed_request).to have_been_requested.once
        expect(response.error).to be_nil
        expect(response.data.class).to eq(Licensify::Services::V1::GetCustomerLicensesResponse)
        expect(response.data.customerLicenses).to eq([])
      end
    end

    describe "#get_licensee_ids" do
      it "creates request and parses the response" do
        request_params = {
          customerId: 10,
          product: "PRODUCT_SDLC",
          enablementReasons: ["ENABLEMENT_REASON_ORG_MEMBERSHIP"]
        }
        stubbed_request = stub_twirp_rpc("licensify.services.v1.CustomerLicenseService", "GetLicenseeIds")
                          .with(twirp_request(
                                  "licensify.services.v1.GetLicenseeIdsRequest",
                                  **request_params
                                ))
                          .to_return twirp_response(
                            "licensify.services.v1.GetLicenseeIdsResponse",
                            licenseeIds: []
                          )

        response = client.get_licensee_ids(**request_params)

        expect(stubbed_request).to have_been_requested.once
        expect(response.error).to be_nil
        expect(response.data.class).to eq(Licensify::Services::V1::GetLicenseeIdsResponse)
        expect(response.data.licenseeIds).to eq([])
      end
    end

    describe "#sync_organization_memberships" do
      it "creates request and parses the response" do
        request_params = { entityType: "SYNC_ENTITY_TYPE_CUSTOMER", entityId: 2 }
        stubbed_request = stub_twirp_rpc("licensify.services.v1.CustomerLicenseService", "SyncOrganizationMemberships")
                          .with(twirp_request(
                                  "licensify.services.v1.SyncOrganizationMembershipsRequest",
                                  **request_params
                                ))
                          .to_return twirp_response(
                            "licensify.services.v1.SyncOrganizationMembershipsResponse",
                            jobId: "1234"
                          )

        response = client.sync_organization_memberships(**request_params)

        expect(stubbed_request).to have_been_requested.once
        expect(response.error).to be_nil
        expect(response.data.class).to eq(Licensify::Services::V1::SyncOrganizationMembershipsResponse)
        expect(response.data.jobId).to eq("1234")
      end
    end
  end
end
