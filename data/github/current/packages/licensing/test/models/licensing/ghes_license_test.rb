# typed: true
# frozen_string_literal: true

require "test_helper"

class Licensing::GhesLicenseTest < GitHub::TestCase
  skip_enterprise

  include GitHub::LoggerHelper
  include LicensingTestHelpers

  fixtures do
    @business = create(:business)
  end

  setup do
    @azure_blob_service = setup_azure_blob_storage_mock
    Licensing::GhesLicense.any_instance.stubs(:azure_blob_client).returns(@azure_blob_service)
    Licensing::GhesLicense::LicenseKeyGenerator.any_instance.stubs(:generate!)
    @license_key = "fake license key"
    Licensing::GhesLicense::LicenseKeyGenerator.any_instance.stubs(:license_key).returns(@license_key)
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

  context "creates a ghes_license record" do
    test_cases = [
      { name: "bundled_ghas", ghas_expected: true, unbundled_expected: false },
      { name: "unbundled_ghas", ghas_expected: true, unbundled_expected: true },
    ].each do |test_case|
      test "with #{test_case[:name]}" do
        if test_case[:name] == "bundled_ghas"
          @business.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)
          assert @business.advanced_security_purchased?
          assert @business.advanced_security_products_bundled?
        elsif test_case[:name] == "unbundled_ghas"
          @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: User.ghost)
          assert @business.advanced_security_purchased?
          refute @business.advanced_security_products_bundled?
        else
          refute @business.advanced_security_purchased?
        end

        ref_number = "123456"

        current_time = Time.now.utc

        Timecop.freeze(current_time) do
          assert_difference "Licensing::GhesLicense.count", 1 do
            Licensing::GhesLicense.create_metered_ghes_license(business: @business, reference_number: ref_number)
          end
        end

        ghes_license = Licensing::GhesLicense.last
        assert_equal @business, T.must(ghes_license).business
        assert T.must(ghes_license).metered
        assert_equal @business.consumed_ghec_only_users_access_licenses, T.must(ghes_license).seats
        assert_equal test_case[:ghas_expected], T.must(ghes_license).advanced_security_enabled?
        assert_equal test_case[:unbundled_expected], T.must(ghes_license).code_security_enabled?
        assert_equal test_case[:unbundled_expected], T.must(ghes_license).secret_protection_enabled?
        assert_equal 0, T.must(ghes_license).advanced_security_seats
        refute_nil T.must(ghes_license).reference_number
        assert_same_time current_time + 1.year, T.must(ghes_license).expires_at
      end
    end
  end

  test "#job_id" do
    ghes_license = create(:licensing_ghes_license, business: @business)
    assert_equal "metered-server-license-#{ghes_license.id}", ghes_license.job_id
  end

  context "#generate_server_license_key" do
    test "uploads a license key to Azure blob storage" do
      ghes_license = create(:licensing_ghes_license, business: @business)

      stub_license_key_upload(ghes_license, @license_key, @azure_blob_service)

      expected_log_context = {
        Body: "Successfully generated server license key",
        "gh.business.id": @business.id,
        "gh.ghes_license.reference_number": ghes_license.reference_number,
      }

      assert_logged(**expected_log_context) do
        ghes_license.generate_server_license_key
      end
    end

    test "logs an error when license key generation fails" do
      ghes_license = create(:licensing_ghes_license, business: @business)

      Licensing::GhesLicense::LicenseKeyGenerator.any_instance.expects(:generate!)
        .raises(Enterprise::Crypto::Error, "license generation error message")

      expected_log_context = {
        Body: "Failed to generate server license key",
        "exception.type": Enterprise::Crypto::Error.name,
        "exception.message": "license generation error message",
        "gh.business.id": @business.id,
        "gh.ghes_license.reference_number": ghes_license.reference_number,
      }

      assert_logged(**expected_log_context) do
        ghes_license.generate_server_license_key
      end
    end

    test "logs an error when license key upload fails" do
      ghes_license = create(:licensing_ghes_license, business: @business)

      @azure_blob_service.expects(:upload)
        .with(Licensing::GhesLicense::SERVER_KEYS_CONTAINER, "github-enterprise-#{ghes_license.reference_number}.ghl", @license_key)
        .raises(Licensing::AzureBlobClient::UploadError, "original error message")
        .once

      expected_log_context = {
        Body: "Failed to generate server license key",
        "exception.type": Licensing::AzureBlobClient::UploadError.name,
        "exception.message": "original error message",
        "gh.business.id": @business.id,
        "gh.ghes_license.reference_number": ghes_license.reference_number,
      }

      assert_logged(**expected_log_context) do
        ghes_license.generate_server_license_key
      end
    end
  end

  context "#license_key" do
    test "returns the license key from Azure blob storage" do
      ghes_license = create(:licensing_ghes_license, business: @business)

      stub_license_key_get_blob(@azure_blob_service, ghes_license, @license_key)

      assert_equal @license_key, ghes_license.license_key
    end

    test "instruments download" do
      events = subscribe "ghes_license.download"

      ghes_license = create(:licensing_ghes_license, business: @business)

      stub_license_key_get_blob(@azure_blob_service, ghes_license, @license_key)

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
        code_security_enabled: ghes_license.code_security_enabled,
        code_security_licenses: ghes_license.code_security_licenses,
        secret_protection_enabled: ghes_license.secret_protection_enabled,
        secret_protection_licenses: ghes_license.secret_protection_licenses,
        license_expires_at: ghes_license.expires_at,
      }

      assert event = events.pop, "ghes_license.download event was expected"
      assert events.empty?
      assert_equal expected_payload, event.payload
    end
  end

  context "instruments creation" do
    test_cases = [
      { name: "bundled_ghas", ghas_expected: true, unbundled_expected: false },
      { name: "unbundled_ghas", ghas_expected: true, unbundled_expected: true },
    ].each do |test_case|
      test "ghes_license with #{test_case[:name]}" do
        if test_case[:name] == "bundled_ghas"
          @business.mark_advanced_security_as_purchased_for_entity(actor: User.ghost)
          assert @business.advanced_security_purchased?
          assert @business.advanced_security_products_bundled?
        elsif test_case[:name] == "unbundled_ghas"
          @business.mark_advanced_security_as_purchased_for_entity_as_volume_unbundled(actor: User.ghost)
          assert @business.advanced_security_purchased?
          refute @business.advanced_security_products_bundled?
        else
          refute @business.advanced_security_purchased?
        end

        events = subscribe "ghes_license.create"
        ghes_license = create(:licensing_ghes_license, business: @business)

        expected_payload = {
          business: @business.slug,
          business_id: @business.id,
          license_id: ghes_license.id,
          reference_number: ghes_license.reference_number,
          metered: ghes_license.metered,
          seats: ghes_license.seats,
          advanced_security_enabled: test_case[:ghas_expected],
          advanced_security_seats: ghes_license.advanced_security_seats,
          code_security_enabled: test_case[:unbundled_expected],
          code_security_licenses: ghes_license.code_security_licenses,
          secret_protection_enabled: test_case[:unbundled_expected],
          secret_protection_licenses: ghes_license.secret_protection_licenses,
          license_expires_at: ghes_license.expires_at,
        }

        assert event = events.pop, "ghes_license.create event was expected"
        assert events.empty?
        assert_equal expected_payload, event.payload
      end
    end
  end
end
