# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesServerLicensesControllerHttpTest < GitHub::IntegrationTestCase
  include BusinessTestHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
    @enterprise_web_business_id = 3
    @organization = create(:organization)
    @owner = create(:user)
    @business = create(:business, owners: [@owner], organizations: [@organization])
    @business.enterprise_web_business_id = @enterprise_web_business_id
    @business.save!
    @member = @organization.admins.first
  end

  setup do
    @license_id = "abc123"

    @stubbed_request = stub_request(
      :get,
      "https://enterprise.github.localhost/api/businesses/#{@enterprise_web_business_id}/licenses/#{@license_id}/download",
    )
  end

  context "GET /enterprises/:business/server_licenses/:id", skip_enterprise: true do
    test_business_access do
      @stubbed_request.to_return(status: 200)

      get "/enterprises/#{@business.to_param}/server_licenses/#{@license_id}"
    end

    test "responds with the license data as an attachment" do
      as @owner

      @stubbed_request.to_return(
        body: "license data",
        status: 200,
      )

      get "/enterprises/#{@business.to_param}/server_licenses/#{@license_id}"

      assert_response :success
      assert_equal "license data", response.body
      assert_match /attachment; filename="github-enterprise-#{@license_id}.ghl"/, response.headers["Content-Disposition"]
    end

    test "responds with a 404 when the enterprise web isn't successful" do
      as @owner

      @stubbed_request.to_return(
        status: 500,
      )

      get "/enterprises/#{@business.to_param}/server_licenses/#{@license_id}"

      assert_response :not_found
    end

    test "responds with a 404 when the enterprise web request raises an error" do
      as @owner

      @stubbed_request.to_raise(Faraday::TimeoutError)

      get "/enterprises/#{@business.to_param}/server_licenses/#{@license_id}"

      assert_response :not_found
    end

    test "instruments a download event for the audit log" do
      as @owner
      @stubbed_request.to_return(
        body: "license data",
        status: 200,
      )

      events = subscribe "business.enterprise_server_license_download"

      get "/enterprises/#{@business.to_param}/server_licenses/#{@license_id}"

      expected_payload = {
        license_id: @license_id,
        user: @owner.display_login,
        user_id: @owner.id,
        business: @business.slug,
        business_id: @business.id,
      }

      event = events.pop
      assert_subset_hash expected_payload, event.payload
    end
  end
end
