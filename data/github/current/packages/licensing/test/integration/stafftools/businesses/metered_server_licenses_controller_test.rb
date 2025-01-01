# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsBusinessesMeteredServerLicensesControllerHttpTest < GitHub::IntegrationTestCase
  include LicensingTestHelpers

  fixtures do
    @staff = create(:staff_admin_user)
    @owner = create(:user)
    @member = create(:user)
    @organization = create(:organization, admin: @owner)
    @organization.add_member(@member)
    @business = create(:business, owners: [@owner], organizations: [@organization])
    @business.customer.update(metered_plan: true)
  end

  setup do
    @azure_blob_service = setup_azure_blob_storage_mock
    disable_feature_flag(:licensing_server_users_from_licensify, @business)
  end

  context "POST /stafftools/enterprises/:slug/metered_server_licenses" do
    if GitHub.billing_enabled?
      test "renders 404 for non metered_ghes_eligible" do
        @business.update_attribute :trial_expires_at, ::Billing::EnterpriseCloudTrial.trial_length.from_now

        as @staff
        post "/stafftools/enterprises/#{@business.slug}/metered_server_licenses", params: {}, as: :json

        assert_response_not_found
      end

      test "renders 404 for non business owner" do
        as @member
        post "/stafftools/enterprises/#{@business.slug}/metered_server_licenses.json"

        assert_response_not_found
      end

      test "returns creates ghes_license and ghes_keypair records for metered_ghes_eligible" do
        as @staff
        assert_difference "Licensing::GhesLicense.count", 1 do
          post "/stafftools/enterprises/#{@business.slug}/metered_server_licenses", params: {}, as: :json
        end

        assert_response :created

        ghes_license = @business.ghes_licenses.last

        assert ghes_license.metered
        assert ghes_license.advanced_security_enabled?

        expected_body = {
          job_url: job_status_url(ghes_license.job_id),
          download_url: stafftools_metered_server_license_url(id: ghes_license.reference_number),
          license: {
            reference_number: ghes_license.reference_number,
            seats: ghes_license.seats,
            expires_at: ghes_license.expires_at
          }
        }.to_json
        assert_equal response.body, expected_body
      end

      test "uses the number of users consuming enterprise licenses for the ghes_license seats", skip_with_all_emus: true do
        installation = create(:enterprise_installation, owner: @business)

        mock_licensify_sdlc_licensee_ids(@business.customer.id, [@member.id])

        # this user should not be included in the ghes_license.seats because they're a server only user
        create(
          :enterprise_installation_user_account,
          enterprise_installation: installation,
          business_user_account: create(:business_user_account, user: nil, business: @business)
        )

        as @staff
        assert_difference "Licensing::GhesLicense.count", 1 do
          post "/stafftools/enterprises/#{@business.slug}/metered_server_licenses", params: {}, as: :json
        end

        assert_response_success

        ghes_license = @business.ghes_licenses.last

        assert ghes_license.metered
        assert ghes_license.advanced_security_enabled?
        # @member = 1 seat
        assert_equal 1, ghes_license.seats
      end
    end
  end

  context "GET /stafftools/enterprises/:slug/metered_server_licenses/:reference_number" do
    if GitHub.billing_enabled?
      test "renders 404 for non metered_ghes_eligible" do
        @business.update_attribute :trial_expires_at, ::Billing::EnterpriseCloudTrial.trial_length.from_now

        as @staff
        get "/stafftools/enterprises/#{@business.slug}/metered_server_licenses/abc123"

        assert_response_not_found
      end

      test "renders 404 for non business owner" do
        as @member
        get "/stafftools/enterprises/#{@business.slug}/metered_server_licenses/abc123"

        assert_response_not_found
      end

      test "returns the license key as an attachment when it exists for metered_ghes_eligible" do
        ghes_license = create(:licensing_ghes_license, business: @business)
        @azure_blob_service.expects(:get_blob)
          .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ghes_license.reference_number}.ghl")
          .returns([Azure::Storage::Blob::Blob.new, "fake license key"])
          .once

        as @staff
        get "/stafftools/enterprises/#{@business.slug}/metered_server_licenses/#{ghes_license.reference_number}"

        assert_response_success
        assert_equal response.body, "fake license key"
        assert_match /attachment; filename="github-enterprise-#{ghes_license.reference_number}.ghl"/, response.headers["Content-Disposition"]
      end

      test "returns 404 when the ghes_license record does not exist" do
        as @staff
        get "/stafftools/enterprises/#{@business.slug}/metered_server_licenses/abc123"

        assert_response_not_found
      end

      test "returns 404 when the ghes_license record does not have an associated server key" do
        ghes_license = create(:licensing_ghes_license, business: @business)
        @azure_blob_service.expects(:get_blob)
          .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ghes_license.reference_number}.ghl")
          .returns([nil, nil])
          .once

        as @staff
        get "/stafftools/enterprises/#{@business.slug}/metered_server_licenses/#{ghes_license.reference_number}"

        assert_response_not_found
      end
    end
  end
end
