# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::GhesLicenseTest < GitHub::TestCase
  include GitHub::LoggerHelper

  fixtures do
    @business = create(:business)
  end

  setup do
    @azure_blob_client = mock("Azure::Storage::Blob::BlobService")
    Licensing::GhesLicense.any_instance.stubs(:azure_blob_client).returns(@azure_blob_client)
    Licensing::GhesLicense::LicenseKeyGenerator.any_instance.stubs(:generate!)
  end

  test "requires a valid license_type" do
    ghes_license = build(:licensing_ghes_license, license_type: "invalid")
    refute ghes_license.valid?
  end

  test "requires a valid state" do
    ghes_license = build(:licensing_ghes_license, state: "invalid")
    refute ghes_license.valid?
  end

  test "requires a unique reference_number" do
    ghes_license = create(:licensing_ghes_license, business: @business)
    refute build(:licensing_ghes_license, reference_number: ghes_license.reference_number).valid?
  end

  context "#create_metered_ghes_license" do
    test "creates a ghes_license record and uploads a license_key to Azure blob storage" do
      ref_number = "123456"
      license_key = "fake license key"
      Licensing::GhesLicense::LicenseKeyGenerator.any_instance.stubs(:license_key).returns(license_key)
      @azure_blob_client.expects(:upload)
        .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ref_number}.ghl", license_key)
        .once

      current_time = Time.now.utc

      expected_log_context = {
        Body: "Successfully generated server license key",
        "gh.business.id": @business.id,
        "gh.ghes_license.reference_number": ref_number,
      }

      assert_logged(**expected_log_context) do
        Timecop.freeze(current_time) do
          assert_difference "Licensing::GhesLicense.count", 1 do
            Licensing::GhesLicense.create_metered_ghes_license(business: @business, reference_number: ref_number)
          end
        end
      end

      ghes_license = Licensing::GhesLicense.last
      assert_equal @business, T.must(ghes_license).business
      assert T.must(ghes_license).metered
      assert_equal @business.consumed_ghec_only_users_access_licenses, T.must(ghes_license).seats
      assert T.must(ghes_license).advanced_security_enabled?
      assert_equal 0, T.must(ghes_license).advanced_security_seats
      refute_nil T.must(ghes_license).reference_number
      assert_same_time current_time + 1.year, T.must(ghes_license).expires_at
    end

    test "logs an error when license generation fails" do
      ref_number = "123456"
      license_key = "fake license key"
      Licensing::GhesLicense::LicenseKeyGenerator.any_instance.stubs(:license_key).returns(license_key)
      @azure_blob_client.expects(:upload)
        .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ref_number}.ghl", license_key)
        .raises(Licensing::AzureBlobClient::UploadError, "original error message")
        .once

      expected_log_context = {
        Body: "Failed to generate server license key",
        "exception.type": Licensing::AzureBlobClient::UploadError.name,
        "exception.message": "original error message",
        "gh.business.id": @business.id,
        "gh.ghes_license.reference_number": ref_number,
      }

      assert_logged(**expected_log_context) do
        Licensing::GhesLicense.create_metered_ghes_license(business: @business, reference_number: ref_number)
      end
    end
  end

  context "#license_key" do
    test "returns the license key from Azure blob storage" do
      ghes_license = create(:licensing_ghes_license, business: @business)
      license_key = "fake license key"
      @azure_blob_client.expects(:get_blob)
        .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ghes_license.reference_number}.ghl")
        .returns([Azure::Storage::Blob::Blob.new, license_key]).once

      assert_equal license_key, ghes_license.license_key
    end

    test "instruments download" do
      events = subscribe "ghes_license.download"

      ghes_license = create(:licensing_ghes_license, business: @business)
      license_key = "fake license key"
      @azure_blob_client.expects(:get_blob)
        .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ghes_license.reference_number}.ghl")
        .returns([Azure::Storage::Blob::Blob.new, license_key]).once

      ghes_license.license_key

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

      assert event = events.pop, "ghes_license.download event was expected"
      assert events.empty?
      assert_equal expected_payload, event.payload
    end
  end

  test "instruments creation" do
    events = subscribe "ghes_license.create"

    ghes_license = create(:licensing_ghes_license, business: @business)

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

    assert event = events.pop, "ghes_license.create event was expected"
    assert events.empty?
    assert_equal expected_payload, event.payload
  end
end
