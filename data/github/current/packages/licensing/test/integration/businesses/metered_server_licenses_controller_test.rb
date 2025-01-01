# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessesMeteredServerLicensesControllerHttpTest < GitHub::IntegrationTestCase
  include LicensingTestHelpers
  include AuditLog::IntegrationTestHelpers

  fixtures do
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

  context "POST /enterprises/:slug/metered_server_licenses" do
    if GitHub.billing_enabled?
      test "renders 404 for non metered_ghes_eligible" do
        @business.update_attribute :trial_expires_at, 1.day.from_now
        as @owner

        post "/enterprises/#{@business.slug}/metered_server_licenses", params: {}, as: :json
        assert_response_not_found
      end

      test "renders 404 for non business owner" do
        as @member

        post "/enterprises/#{@business.slug}/metered_server_licenses.json"
        assert_response_not_found
      end

      test "returns creates ghes_license and ghes_keypair records for metered_ghes_eligible" do
        as @owner

        assert_difference "Licensing::GhesLicense.count", 1 do
          post "/enterprises/#{@business.slug}/metered_server_licenses", params: {}, as: :json
        end
        assert_response_success

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

        # this user should not be included because they're GHES only user
        create(
          :enterprise_installation_user_account,
          enterprise_installation: installation,
          business_user_account: create(:business_user_account, user: nil, business: @business)
        )

        as @owner

        assert_difference "Licensing::GhesLicense.count", 1 do
          post "/enterprises/#{@business.slug}/metered_server_licenses", params: {}, as: :json
        end
        assert_response_success

        ghes_license = @business.ghes_licenses.last

        assert ghes_license.metered
        assert ghes_license.advanced_security_enabled?
        # @member = 1 seat
        assert_equal 1, ghes_license.seats
      end

      test "instruments a ghes_license.create audit log event" do
        as @owner

        events = assert_performed_audit_entries(count: 1, only: "ghes_license.create") do
          post "/enterprises/#{@business.slug}/metered_server_licenses", params: {}, as: :json
        end

        ghes_license = Licensing::GhesLicense.last

        expected_payload = {
          business: @business.slug,
          business_id: @business.id,
          license_id: T.must(ghes_license).id,
          reference_number: T.must(ghes_license).reference_number,
          metered: T.must(ghes_license).metered,
          seats: T.must(ghes_license).seats,
          advanced_security_enabled: T.must(ghes_license).advanced_security_enabled,
          advanced_security_seats: T.must(ghes_license).advanced_security_seats,
          license_expires_at: T.must(ghes_license).expires_at,
        }

        assert_subset_hash expected_payload, events.first
      end
    end
  end

  context "GET /enterprises/:slug/metered_server_licenses/:reference_number" do
    if GitHub.billing_enabled?
      test "renders 404 for non metered_ghes_eligible" do
        @business.update_attribute :trial_expires_at, 1.day.from_now
        as @owner

        get "/enterprises/#{@business.slug}/metered_server_licenses/abc123"
        assert_response_not_found
      end

      test "renders 404 for non business owner" do
        as @member

        get "/enterprises/#{@business.slug}/metered_server_licenses/abc123"
        assert_response_not_found
      end

      test "returns the license key as an attachment when it exists for metered_ghes_eligible" do
        ghes_license = create(:licensing_ghes_license, business: @business)
        @azure_blob_service.expects(:get_blob)
          .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ghes_license.reference_number}.ghl")
          .returns([Azure::Storage::Blob::Blob.new, "fake license key"])
          .once

        as @owner

        get "/enterprises/#{@business.slug}/metered_server_licenses/#{ghes_license.reference_number}"
        assert_response_success
        assert_equal response.body, "fake license key"
        assert_match /attachment; filename="github-enterprise-#{ghes_license.reference_number}.ghl"/, response.headers["Content-Disposition"]
      end

      test "returns 404 when the ghes_license record does not exist" do
        as @owner

        get "/enterprises/#{@business.slug}/metered_server_licenses/abc123"
        assert_response_not_found
      end

      test "returns 404 when the ghes_license record does not have an associated server key" do
        ghes_license = create(:licensing_ghes_license, business: @business)
        @azure_blob_service.expects(:get_blob)
          .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ghes_license.reference_number}.ghl")
          .returns([nil, nil])
          .once

        as @owner

        get "/enterprises/#{@business.slug}/metered_server_licenses/#{ghes_license.reference_number}"
        assert_response_not_found
      end

      test "instruments a ghes_license.download audit log event" do
        ghes_license = create(:licensing_ghes_license, business: @business)
        @azure_blob_service.expects(:get_blob)
          .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ghes_license.reference_number}.ghl")
          .returns([Azure::Storage::Blob::Blob.new, "fake license key"])
          .once

        as @owner

        events = assert_performed_audit_entries(count: 1, only: "ghes_license.download") do
          get "/enterprises/#{@business.slug}/metered_server_licenses/#{ghes_license.reference_number}"
        end

        expected_payload = {
          business: @business.slug,
          business_id: @business.id,
          license_id: ghes_license.id,
          reference_number: ghes_license.reference_number,
          metered: ghes_license.metered,
          seats: ghes_license.seats,
          advanced_security_enabled: ghes_license.advanced_security_enabled,
          advanced_security_seats: ghes_license.advanced_security_seats,
          license_expires_at: ghes_license.expires_at,
        }

        assert_subset_hash expected_payload, events.first
      end
    end
  end
end
